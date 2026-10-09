import Foundation
import GRDB

/// The app's single SQLite database. All reads and writes go through `reader` / `writer`.
nonisolated final class AppDatabase: Sendable {
    let writer: any DatabaseWriter
    var reader: any DatabaseReader { writer }

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    static func openShared() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: FileStore.databaseURL.path, configuration: config)
        return try AppDatabase(pool)
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    // Migrations are append-only: never edit a shipped migration, add a new one.
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "document") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("authors", .text)
                t.column("year", .integer)
                t.column("sourceURL", .text)
                t.column("doi", .text)
                t.column("arxivID", .text)
                t.column("contentHash", .text).notNull().unique()
                t.column("fileName", .text).notNull()
                t.column("pageCount", .integer).notNull()
                t.column("addedAt", .datetime).notNull()
                t.column("openedAt", .datetime)
                t.column("updatedAt", .datetime).notNull()
                t.column("lastPage", .integer).notNull().defaults(to: 0)
                t.column("lastPageY", .double)
                t.column("progress", .double).notNull().defaults(to: 0)
                t.column("status", .text).notNull()
                t.column("isIndexed", .boolean).notNull().defaults(to: false)
            }

            // Full text of every page, for global search and in-document search.
            try db.create(virtualTable: "pageText", using: FTS5()) { t in
                t.tokenizer = .porter(wrapping: .unicode61())
                t.column("documentID").notIndexed()
                t.column("page").notIndexed()
                t.column("text")
            }
        }

        migrator.registerMigration("v2-annotations") { db in
            // Text marks: highlight / underline / strikethrough, optionally flagged and annotated.
            try db.create(table: "highlight") { t in
                t.primaryKey("id", .text)
                t.column("documentID", .text).notNull().indexed()
                    .references("document", onDelete: .cascade)
                t.column("page", .integer).notNull()
                t.column("style", .text).notNull()
                t.column("flag", .text)
                t.column("rects", .text).notNull()    // JSON [[x, y], [w, h]] in page space
                t.column("text", .text).notNull()
                t.column("note", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Pencil ink: one PencilKit drawing per page.
            try db.create(table: "ink") { t in
                t.column("documentID", .text).notNull()
                    .references("document", onDelete: .cascade)
                t.column("page", .integer).notNull()
                t.column("drawing", .blob).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.primaryKey(["documentID", "page"])
            }
        }

        migrator.registerMigration("v3-notebook") { db in
            // Free-form notes for a whole document (the notebook's top section).
            try db.create(table: "documentNote") { t in
                t.primaryKey("documentID", .text)
                    .references("document", onDelete: .cascade)
                t.column("body", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v4-export") { db in
            // File name of the document's annotated export in Files › On My iPad › Marginalia,
            // so re-saving overwrites the same file.
            try db.alter(table: "document") { t in
                t.add(column: "exportFileName", .text)
            }
        }

        return migrator
    }
}
