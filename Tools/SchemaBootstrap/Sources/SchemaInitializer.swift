import Foundation
import SwiftData
import CoreData

enum SchemaInitializationError: LocalizedError {
    case unavailableBuild, unavailableModel

    var errorDescription: String? {
        switch self {
        case .unavailableBuild: return "Schema initialization is available only in the dedicated development setup build."
        case .unavailableModel: return "SwiftData could not create the managed object model."
        }
    }
}

enum SchemaInitializer {
    static func initialize(containerIdentifier: String) async throws {
        #if DEBUG && SHEKATI_SCHEMA_BOOTSTRAP
        // No account login is needed on the build runner. The signed, iCloud-enabled phone performs this operation.
        try await Task.detached(priority: .userInitiated) {
            let directory = URL.applicationSupportDirectory
                .appending(path: "SchemaBootstrap", directoryHint: .isDirectory)
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            // Apple's SwiftData/Core Data integration generates all optional fields and asset counterparts.
            // A temporary store prevents schema setup from inserting records in the regular app's local store.
            try autoreleasepool {
                guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [ChequeRecord.self, AppConfiguration.self]) else {
                    throw SchemaInitializationError.unavailableModel
                }
                let description = NSPersistentStoreDescription(url: directory.appending(path: "Schema.store"))
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
                description.shouldAddStoreAsynchronously = false
                let container = NSPersistentCloudKitContainer(name: "ShekatiSchemaBootstrap", managedObjectModel: model)
                container.persistentStoreDescriptions = [description]
                var loadError: Error?
                container.loadPersistentStores { _, error in loadError = error }
                if let loadError { throw loadError }
                defer {
                    for store in container.persistentStoreCoordinator.persistentStores {
                        try? container.persistentStoreCoordinator.remove(store)
                    }
                }
                // Creates temporary CKRecords for every model type, uploads them, then removes them.
                // Production builds of the regular app do not compile or call this separate target.
                try container.initializeCloudKitSchema(options: [])
            }
        }.value
        #else
        throw SchemaInitializationError.unavailableBuild
        #endif
    }
}
