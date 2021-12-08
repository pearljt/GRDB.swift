import GRDB

class DatabaseQueueBackupTests: BackupTestCase {
    
    func testDatabaseWriterBackup() throws {
        // SQLCipher can't backup encrypted databases: use a pristine Configuration
        let source: DatabaseWriter = try makeDatabaseQueue(filename: "source.sqlite", configuration: Configuration())
        let destination: DatabaseWriter = try makeDatabaseQueue(filename: "destination.sqlite", configuration: Configuration())
        try testDatabaseWriterBackup(from: source, to: destination)
    }
    
    func testDatabaseBackup() throws {
        let source: DatabaseWriter = try makeDatabaseQueue(filename: "source.sqlite", configuration: Configuration())
        let destination: DatabaseWriter = try makeDatabaseQueue(filename: "destination.sqlite", configuration: Configuration())
        try testDatabaseBackup(from: source, to: destination)
    }
}
