import Foundation
import CloudKit
import CoreData
import Network
import Observation

// The owner is main-actor isolated, but ARC may release it on any thread.
// Keep thread-safe observer/monitor cleanup in an ordinary lifetime object.
private final class SyncMonitorLifetime {
    var observers: [NSObjectProtocol] = []
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "Shekati.Network")

    deinit {
        monitor.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}

@MainActor @Observable
final class SyncMonitor {
    enum State: Equatable { case checking, available, syncing, synced, offline, unavailable, failed, localOnly }
    typealias AccountStatusProvider = @MainActor () async throws -> CKAccountStatus
    private struct CompletedEvent {
        let endDate: Date
        let succeeded: Bool
        let detail: String?
    }
    private(set) var state: State = .checking
    private(set) var lastSyncDate: Date?
    private(set) var detail: String?
    private var networkAvailable = true
    private var cloudAvailable: Bool?
    private var accountFailure: String?
    private var activeEvents: Set<UUID> = []
    private var completedEvents: [NSPersistentCloudKitContainer.EventType: CompletedEvent] = [:]
    @ObservationIgnored private let lifetime = SyncMonitorLifetime()
    @ObservationIgnored private let accountStatusProvider: AccountStatusProvider
    private let localOnly: Bool

    init(localOnlyReason: String? = nil, observeChanges: Bool = true,
         accountStatusProvider: AccountStatusProvider? = nil) {
        localOnly = localOnlyReason != nil
        detail = localOnlyReason
        self.accountStatusProvider = accountStatusProvider ?? {
            let identifier = Bundle.main.object(forInfoDictionaryKey: "ShekatiCloudContainerIdentifier") as? String
            let container = identifier.map(CKContainer.init(identifier:)) ?? CKContainer.default()
            return try await container.accountStatus()
        }
        if localOnly { state = .localOnly }
        // Tests exercise the actual state transitions without starting live observers/network checks.
        guard observeChanges else { return }
        lifetime.observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor [weak self] in self?.receive(event) }
        })
        lifetime.observers.append(NotificationCenter.default.addObserver(forName: .CKAccountChanged,
                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        })
        lifetime.monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.updateNetworkAvailability(online)
            }
        }
        lifetime.monitor.start(queue: lifetime.queue)
    }

    func refresh() async {
        guard !localOnly else { state = .localOnly; return }
        guard networkAvailable else { state = .offline; return }
        do {
            let status = try await accountStatusProvider()
            cloudAvailable = status == .available
            accountFailure = nil
        } catch {
            accountFailure = error.localizedDescription
        }
        updateState()
    }

    func updateNetworkAvailability(_ available: Bool) async {
        networkAvailable = available
        guard !localOnly else { return }
        if available { await refresh() }
        else { updateState() }
    }

    private func receive(_ event: NSPersistentCloudKitContainer.Event) {
        receiveEvent(type: event.type, identifier: event.identifier, endDate: event.endDate,
                     succeeded: event.succeeded, errorDescription: event.error?.localizedDescription)
    }

    // Adapter seam avoids constructing Apple's read-only event objects in hosted unit tests.
    func receiveEvent(type: NSPersistentCloudKitContainer.EventType, identifier: UUID,
                      endDate: Date?, succeeded: Bool, errorDescription: String? = nil) {
        guard !localOnly else { return }
        guard let endDate else {
            activeEvents.insert(identifier)
            updateState()
            return
        }
        activeEvents.remove(identifier)
        // Late delivery of an older completion must not erase a newer failure or success.
        if completedEvents[type].map({ $0.endDate <= endDate }) ?? true {
            completedEvents[type] = CompletedEvent(endDate: endDate, succeeded: succeeded,
                                                   detail: errorDescription)
        }
        if succeeded && type != .setup {
            if lastSyncDate.map({ $0 < endDate }) ?? true {
                lastSyncDate = endDate
            }
        }
        updateState()
    }

    private func updateState() {
        guard !localOnly else { state = .localOnly; return }
        let failure = completedEvents.values.filter { !$0.succeeded }.max { $0.endDate < $1.endDate }
        detail = failure?.detail ?? accountFailure
        if !networkAvailable { state = .offline }
        else if accountFailure != nil { state = .failed }
        else if cloudAvailable == false { state = .unavailable }
        else if !activeEvents.isEmpty { state = .syncing }
        else if failure != nil { state = .failed }
        else if lastSyncDate != nil { state = .synced }
        else if cloudAvailable == true || completedEvents[.setup]?.succeeded == true { state = .available }
        else { state = .checking }
    }
}
