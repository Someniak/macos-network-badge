// ---------------------------------------------------------
// TileCacheTests.swift — Tests for offline map tile caching
//
// Verifies that map tiles can be stored and retrieved from
// disk, and that the cache directory structure is correct.
// ---------------------------------------------------------

import XCTest
@testable import NetworkBadge

final class TileCacheTests: XCTestCase {

    /// Creates a fresh temporary tile cache for each test
    private func makeTempCache() -> TileCache {
        let tempDir = NSTemporaryDirectory() + "test_tiles_\(UUID().uuidString)"
        return TileCache(directory: tempDir)
    }

    // MARK: - Basic Operations

    /// Storing and loading a tile should return the same data
    func testStoreAndLoad() {
        let cache = makeTempCache()
        let tileData = Data("fake-png-data".utf8)

        cache.store(data: tileData, x: 8399, y: 5468, z: 14)
        let loaded = cache.load(x: 8399, y: 5468, z: 14)

        XCTAssertEqual(loaded, tileData)
    }

    /// Loading a non-existent tile should return nil
    func testLoadMissing() {
        let cache = makeTempCache()
        let loaded = cache.load(x: 999, y: 999, z: 1)
        XCTAssertNil(loaded)
    }

    /// Tile path should follow the {z}/{x}/{y}.png convention
    func testTilePath() {
        let cache = makeTempCache()
        let path = cache.tilePath(x: 100, y: 200, z: 10)

        XCTAssertTrue(path.hasSuffix("/10/100/200.png"))
    }

    /// Multiple tiles at different coordinates should not interfere
    func testMultipleTiles() {
        let cache = makeTempCache()

        let tile1 = Data("tile-1".utf8)
        let tile2 = Data("tile-2".utf8)
        let tile3 = Data("tile-3".utf8)

        cache.store(data: tile1, x: 0, y: 0, z: 1)
        cache.store(data: tile2, x: 1, y: 0, z: 1)
        cache.store(data: tile3, x: 0, y: 1, z: 1)

        XCTAssertEqual(cache.load(x: 0, y: 0, z: 1), tile1)
        XCTAssertEqual(cache.load(x: 1, y: 0, z: 1), tile2)
        XCTAssertEqual(cache.load(x: 0, y: 1, z: 1), tile3)
    }

    /// Cache size should reflect stored data
    func testCacheSize() {
        let cache = makeTempCache()

        // Empty cache should be 0
        XCTAssertEqual(cache.totalCacheSize(), 0)

        // Store some data
        let data = Data(repeating: 0xFF, count: 1024) // 1KB
        cache.store(data: data, x: 0, y: 0, z: 1)

        XCTAssertGreaterThanOrEqual(cache.totalCacheSize(), 1024)
    }

    /// Formatted cache size should produce a human-readable string
    func testFormattedCacheSize() {
        let cache = makeTempCache()
        let formatted = cache.formattedCacheSize()
        // Should be "Zero KB" or similar for empty cache
        XCTAssertFalse(formatted.isEmpty)
    }

    /// Overwriting a tile should replace the old data
    func testOverwrite() {
        let cache = makeTempCache()

        let oldData = Data("old-tile".utf8)
        let newData = Data("new-tile".utf8)

        cache.store(data: oldData, x: 0, y: 0, z: 1)
        cache.store(data: newData, x: 0, y: 0, z: 1)

        XCTAssertEqual(cache.load(x: 0, y: 0, z: 1), newData)
    }
}
