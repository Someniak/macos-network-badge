// ---------------------------------------------------------
// TileCache.swift — Offline map tile caching
//
// Caches MapKit tile images to disk so the quality map works
// without an internet connection. Uses a custom MKTileOverlay
// that intercepts tile requests and serves cached versions.
//
// Tiles are stored under ~/.networkbadge/tiles/ organized by
// zoom level: tiles/{z}/{x}/{y}.png
//
// The cache grows as the user views different map regions.
// Old tiles are NOT deleted (they're small, ~20KB each).
// ---------------------------------------------------------

import Foundation
import MapKit

// MARK: - Tile Cache Manager

/// Manages offline map tile storage on disk.
///
/// Tiles are PNG images organized by zoom/x/y coordinates:
///   ~/.networkbadge/tiles/14/8399/5468.png
///
/// Each tile is typically 10-30KB, so even thousands of tiles
/// use only a few hundred MB of disk space.
final class TileCache {

    /// Root directory for cached tiles
    let cacheDirectory: String

    init(directory: String? = nil) {
        if let directory = directory {
            self.cacheDirectory = directory
        } else {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            self.cacheDirectory = "\(homeDir)/.networkbadge/tiles"
        }

        // Create the root tiles directory
        try? FileManager.default.createDirectory(
            atPath: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// Returns the file path for a tile at the given coordinates.
    /// Format: {cacheDir}/{z}/{x}/{y}.png
    func tilePath(x: Int, y: Int, z: Int) -> String {
        return "\(cacheDirectory)/\(z)/\(x)/\(y).png"
    }

    /// Stores tile data to disk.
    func store(data: Data, x: Int, y: Int, z: Int) {
        let path = tilePath(x: x, y: y, z: z)
        let dir = (path as NSString).deletingLastPathComponent

        // Create zoom/x directory if needed
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Write tile data to disk
        try? data.write(to: URL(fileURLWithPath: path))
    }

    /// Loads cached tile data from disk. Returns nil if not cached.
    func load(x: Int, y: Int, z: Int) -> Data? {
        let path = tilePath(x: x, y: y, z: z)
        return FileManager.default.contents(atPath: path)
    }

    /// Returns the total size of cached tiles in bytes.
    func totalCacheSize() -> UInt64 {
        var totalSize: UInt64 = 0
        let enumerator = FileManager.default.enumerator(atPath: cacheDirectory)
        while let file = enumerator?.nextObject() as? String {
            if file.hasSuffix(".png") {
                let fullPath = "\(cacheDirectory)/\(file)"
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? UInt64 {
                    totalSize += size
                }
            }
        }
        return totalSize
    }

    /// Human-readable cache size string (e.g. "14.2 MB")
    func formattedCacheSize() -> String {
        let bytes = totalCacheSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Caching Tile Overlay

/// A custom MKTileOverlay that caches tiles to disk for offline use.
///
/// How it works:
///   1. When MapKit requests a tile, check the local cache first
///   2. If cached → return immediately (works offline!)
///   3. If not cached → fetch from the tile server, cache it, then return
///
/// This means the map gradually becomes available offline as the
/// user views different regions.
final class CachingTileOverlay: MKTileOverlay {

    /// The tile cache for persistent storage
    private let cache: TileCache

    /// Initialize with a tile server URL template and cache.
    ///
    /// - Parameters:
    ///   - urlTemplate: OpenStreetMap-style URL template with {x}, {y}, {z} placeholders.
    ///                  Example: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    ///   - cache: The tile cache to store/retrieve tiles from
    init(urlTemplate: String, cache: TileCache) {
        self.cache = cache
        super.init(urlTemplate: urlTemplate)
        self.canReplaceMapContent = true
    }

    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        let x = path.x
        let y = path.y
        let z = path.z

        // Step 1: Try to load from disk cache
        if let cachedData = cache.load(x: x, y: y, z: z) {
            result(cachedData, nil)
            return
        }

        // Step 2: Not cached — fetch from network
        let url = self.url(forTilePath: path)
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                result(nil, error)
                return
            }

            // Step 3: Cache the fetched tile to disk
            self?.cache.store(data: data, x: x, y: y, z: z)

            // Step 4: Return the tile data to MapKit
            result(data, nil)
        }.resume()
    }
}
