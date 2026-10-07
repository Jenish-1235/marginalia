import Foundation
import Observation

/// Long-lived services shared by every window.
@Observable
final class AppEnvironment {
    let database: AppDatabase
    let library: LibraryModel

    init(database: AppDatabase) {
        self.database = database
        self.library = LibraryModel(database: database)
    }

    static func live() -> AppEnvironment {
        #if DEBUG
        // UI tests start from an empty library.
        if ProcessInfo.processInfo.environment["MARGINALIA_RESET"] == "1" {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: FileStore.databaseURL.path + suffix)
            }
            for url in (try? FileManager.default.contentsOfDirectory(
                at: FileStore.libraryDirectory, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: url)
            }
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        }
        #endif
        do {
            return AppEnvironment(database: try AppDatabase.openShared())
        } catch {
            fatalError("Could not open the library database: \(error)")
        }
    }
}
