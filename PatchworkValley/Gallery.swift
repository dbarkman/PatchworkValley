import Foundation
import Observation
import UIKit
import ValleyCore

/// A valley the player saved to the gallery.
struct GalleryEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let valley: Int
    /// Coins the valley earned, not counting the finishing bonus.
    let coins: Int
    let date: Date
    let picture: ValleyPicture
}

/// The player's saved valleys, newest first: an index file plus a full picture and a
/// thumbnail per valley, in Application Support. Reset Player leaves it alone; Reset Everything empties it.
@Observable
final class Gallery {
    private(set) var entries: [GalleryEntry] = []

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var thumbnails: [UUID: UIImage] = [:]
    /// Counts wipes, so a save that finishes after one is dropped rather than written into the empty gallery.
    @ObservationIgnored private var generation = 0

    private var indexURL: URL { folder.appending(path: "gallery.json") }

    init(folder: URL = URL.applicationSupportDirectory.appending(path: "Gallery")) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: indexURL) else { return }
        if let saved = try? JSONDecoder().decode([GalleryEntry].self, from: data) {
            entries = saved
        } else {
            // Never write over an index that can't be read: keep it aside, pictures and all.
            let aside = folder.appending(path: "gallery-unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: indexURL, to: aside)
        }
    }

    /// Draws the valley and saves it, drawing and writing off the main thread.
    /// Returns nil if it couldn't be written.
    @discardableResult
    func add(_ picture: ValleyPicture, valley: Int, coins: Int) async -> GalleryEntry? {
        let entry = GalleryEntry(id: UUID(), valley: valley, coins: coins, date: .now, picture: picture)
        let startedIn = generation
        let imageURL = imageURL(for: entry)
        let thumbnailURL = thumbnailURL(for: entry)
        let thumbnail = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let full = ValleyArt.image(of: picture, longestSide: 2048)
            let thumbnail = ValleyArt.image(of: picture, longestSide: 600)
            guard let fullData = full.pngData(), let thumbnailData = thumbnail.pngData() else { return nil }
            do {
                try fullData.write(to: imageURL, options: .atomic)
                try thumbnailData.write(to: thumbnailURL, options: .atomic)
            } catch {
                return nil
            }
            return thumbnail
        }.value
        guard let thumbnail, generation == startedIn else {
            removeFiles(for: entry)
            return nil
        }
        entries.insert(entry, at: 0)
        do {
            try saveIndex()
        } catch {
            entries.removeAll { $0.id == entry.id }
            removeFiles(for: entry)
            return nil
        }
        thumbnails[entry.id] = thumbnail
        return entry
    }

    func delete(_ entry: GalleryEntry) {
        entries.removeAll { $0.id == entry.id }
        thumbnails[entry.id] = nil
        removeFiles(for: entry)
        try? saveIndex()
    }

    /// Deletes every saved valley and everything else in the folder (unreadable indexes set aside
    /// included), leaving the empty folder a fresh install has.
    func removeAll() {
        generation += 1
        entries = []
        thumbnails = [:]
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func thumbnail(for entry: GalleryEntry) -> UIImage? {
        if let cached = thumbnails[entry.id] { return cached }
        let image = UIImage(contentsOfFile: thumbnailURL(for: entry).path(percentEncoded: false))
        thumbnails[entry.id] = image
        return image
    }

    /// The full picture, redrawn from the saved valley if its file is missing.
    func image(for entry: GalleryEntry) -> UIImage {
        UIImage(contentsOfFile: imageURL(for: entry).path(percentEncoded: false))
            ?? ValleyArt.image(of: entry.picture, longestSide: 2048)
    }

    private func imageURL(for entry: GalleryEntry) -> URL {
        folder.appending(path: "\(entry.id.uuidString).png")
    }

    private func thumbnailURL(for entry: GalleryEntry) -> URL {
        folder.appending(path: "\(entry.id.uuidString)-thumb.png")
    }

    private func removeFiles(for entry: GalleryEntry) {
        try? FileManager.default.removeItem(at: imageURL(for: entry))
        try? FileManager.default.removeItem(at: thumbnailURL(for: entry))
    }

    private func saveIndex() throws {
        try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
    }
}
