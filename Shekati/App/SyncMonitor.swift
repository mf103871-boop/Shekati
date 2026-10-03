import Foundation
import CloudKit
import CoreData
import Network
import Observation

@MainActor @Observable
final class SyncMonitor {
    enum State { case checking, available, syncing, synced, offline, unavailable, failed, localOnly }
    private(set) var state: State = .checking
    private(set) var lastSyncDate: Date?
    private(set) var detail: String?
    private var networkAvailable = true
    private var cloudAvailable = false
    private var observers: [NSObjectProtocol] = []
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Shekati.Network")
    private let localOnly: Bool

    init(localOnlyReason: String? = nil) {
        localOnly = localOnlyReason != nil
        detail = localOnlyReason
        if localOnly { state = .localOnly }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor [weak self] in self?.receive(event) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .CKAccountChanged,
                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        })
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.networkAvailable = online
                if !self.localOnly {
                    if !online { self.state = .offline }
                    else { await self.refresh() }
                }
            }
        }
        monitor.start(queue: queue)
    }

    func refresh() async {
        guard !localOnly else { state = .localOnly; return }
        guard networkAvailable else { state = .offline; return }
        do {
            let identifier = Bundle.main.object(forInfoDictionaryKey: "ShekatiCloudContainerIdentifier") as? String
            let container = identifier.map(CKContainer.init(identifier:)) ?? CKContainer.default()
            let status = try await container.accountStatus()
            cloudAvailable = status == .available
            if cloudAvailable {
                if state != .syncing { state = lastSyncDate == nil ? .available : .synced }
                detail = nil
            } else {
                state = .unavailable
                detail = nil
            }
        } catch {
            state = .failed
            detail = error.localizedDescription
        }
    }

    private func receive(_ event: NSPersistentCloudKitContainer.Event) {
        guard !localOnly else { return }
        if event.endDate == nil { state = .syncing; return }
        if event.succeeded {
            if event.type == .setup {
                state = networkAvailable ? .available : .offline
                return
            }
            lastSyncDate = event.endDate
            state = networkAvailable ? .synced : .offline
            detail = nil
        } else {
            state = networkAvailable ? .failed : .offline
            detail = event.error?.localizedDescription
        }
    }

    deinit {
        monitor.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
