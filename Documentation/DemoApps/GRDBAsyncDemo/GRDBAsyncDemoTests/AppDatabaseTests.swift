import XCTest
import GRDB
@testable import GRDBAsyncDemo

class AppDatabaseTests: XCTestCase {
    func test_database_schema() throws {
        // Given an empty database
        let dbQueue = DatabaseQueue()
        
        // When we instantiate an AppDatabase
        _ = try AppDatabase(dbQueue)
        
        // Then the player table exists, with id, name & score columns
        try dbQueue.read { db in
            try XCTAssert(db.tableExists("player"))
            let columns = try db.columns(in: "player")
            let columnNames = Set(columns.map { $0.name })
            XCTAssertEqual(columnNames, ["id", "name", "score"])
        }
    }
    
    func test_savePlayer_inserts() async throws {
        // Given an empty players database
        let dbQueue = DatabaseQueue()
        let appDatabase = try AppDatabase(dbQueue)
        
        // When we save a new player
        var player = Player(id: nil, name: "Arthur", score: 100)
        try await appDatabase.savePlayer(&player)
        
        // Then the player exists in the database
        try XCTAssertTrue(dbQueue.read(player.exists))
    }
    
    func test_savePlayer_updates() async throws {
        // Given a players database that contains a player
        let dbQueue = DatabaseQueue()
        let appDatabase = try AppDatabase(dbQueue)
        var player = Player(id: nil, name: "Arthur", score: 100)
        player = try await dbQueue.write { [player] db in
            var player = player
            try player.insert(db)
            return player
        }
        
        // When we modify and save the player
        player.name = "Barbara"
        player.score = 1000
        try await appDatabase.savePlayer(&player)
        
        // Then the player has been updated in the database
        let fetchedPlayer = try await dbQueue.read { [player] db in
            try XCTUnwrap(Player.fetchOne(db, key: player.id))
        }
        XCTAssertEqual(fetchedPlayer, player)
    }
    
    func test_deletePlayers() async throws {
        // Given a players database that contains four players
        let dbQueue = DatabaseQueue()
        let appDatabase = try AppDatabase(dbQueue)
        let playerIds: [Int64] = try await dbQueue.write { db in
            var player1 = Player(id: nil, name: "Arthur", score: 100)
            var player2 = Player(id: nil, name: "Barbara", score: 200)
            var player3 = Player(id: nil, name: "Craig", score: 150)
            var player4 = Player(id: nil, name: "David", score: 120)
            
            try player1.insert(db)
            try player2.insert(db)
            try player3.insert(db)
            try player4.insert(db)
            
            return try Player.selectID().fetchAll(db)
        }
        
        // When we delete two players
        let deletedId1 = playerIds[0]
        let deletedId2 = playerIds[2]
        try await appDatabase.deletePlayers(ids: [deletedId1, deletedId2])
        
        // Then the deleted players no longer exist
        try await dbQueue.read { db in
            try XCTAssertNil(Player.fetchOne(db, id: deletedId1))
            try XCTAssertNil(Player.fetchOne(db, id: deletedId2))
        }
        
        // Then the database still contains two players
        try XCTAssertEqual(dbQueue.read(Player.fetchCount), 2)
    }
    
    func test_deleteAllPlayers() async throws {
        // Given a players database that contains players
        let dbQueue = DatabaseQueue()
        let appDatabase = try AppDatabase(dbQueue)
        try await dbQueue.write { db in
            var player1 = Player(id: nil, name: "Arthur", score: 100)
            var player2 = Player(id: nil, name: "Barbara", score: 200)
            var player3 = Player(id: nil, name: "Craig", score: 150)
            var player4 = Player(id: nil, name: "David", score: 120)
            
            try player1.insert(db)
            try player2.insert(db)
            try player3.insert(db)
            try player4.insert(db)
        }
        
        // When we delete all players
        try await appDatabase.deleteAllPlayers()
        
        // Then the database does not contain any player
        try XCTAssertEqual(dbQueue.read(Player.fetchCount), 0)
    }
    
    func test_refreshPlayers_populates_an_empty_database() async throws {
        // Given an empty players database
        let dbQueue = DatabaseQueue()
        let appDatabase = try AppDatabase(dbQueue)
        
        // When we refresh players
        try await appDatabase.refreshPlayers()
        
        // Then the database is not empty
        try XCTAssert(dbQueue.read(Player.fetchCount) > 0)
    }
    
    func test_createRandomPlayersIfEmpty_populates_an_empty_database() throws {
        // Given an empty players database
        let dbQueue = DatabaseQueue()
        let appDatabase = try AppDatabase(dbQueue)
        
        // When we create random players
        try appDatabase.createRandomPlayersIfEmpty()
        
        // Then the database is not empty
        try XCTAssert(dbQueue.read(Player.fetchCount) > 0)
    }
    
    func test_createRandomPlayersIfEmpty_does_not_modify_a_non_empty_database() throws {
        // Given a players database that contains one player
        let dbQueue = DatabaseQueue()
        let appDatabase = try AppDatabase(dbQueue)
        var player = Player(id: nil, name: "Arthur", score: 100)
        try dbQueue.write { db in
            try player.insert(db)
        }
        
        // When we create random players
        try appDatabase.createRandomPlayersIfEmpty()
        
        // Then the database still only contains the original player
        let players = try dbQueue.read(Player.fetchAll)
        XCTAssertEqual(players, [player])
    }
}
