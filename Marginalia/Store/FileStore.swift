import Foundation

/// On-disk layout. Source PDFs are never modified after import.
///
///     Application Support/Marginalia/
///       marginalia.sqlite
///       Library/<document id>.pdf
///     Caches/Thumbnails/<document id>.jpg
nonisolated enum FileStore {
    static let root: URL = directory(
        URL.applicationSupportDirectory.appending(path: "Marginalia", directoryHint: .isDirectory))

    static let libraryDirectory: URL = directory(
        root.appending(path: "Library", directoryHint: .isDirectory))

    static let thumbnailsDirectory: URL = directory(
        URL.cachesDirectory.appending(path: "Thumbnails", directoryHint: .isDirectory))

    static var databaseURL: URL { root.appending(path: "marginalia.sqlite") }

    static func fileURL(for document: Document) -> URL {
        libraryDirectory.appending(path: document.fileName)
    }

    static func thumbnailURL(for documentID: String) -> URL {
        thumbnailsDirectory.appending(path: "\(documentID).jpg")
    }

    static func removeFiles(for document: Document) {
        try? FileManager.default.removeItem(at: fileURL(for: document))
        try? FileManager.default.removeItem(at: thumbnailURL(for: document.id))
    }

    private static func directory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
