import Foundation
import DriveQuizKit

@MainActor
protocol ProgressStoring: AnyObject {
    func load() -> PlayerProgress
    func save(_ progress: PlayerProgress)
}

/// JSON on disk in Application Support. No backend, no account, per the brief.
///
/// Every failure path returns fresh progress rather than throwing. Losing a
/// streak is bad; refusing to start the game because a file is corrupt is
/// worse, and the driver is already moving.
@MainActor
final class FileProgressStore: ProgressStoring {

    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cached: PlayerProgress?

    /// Set when the last load hit a corrupt file, so the UI can say so.
    private(set) var lastLoadFailed = false

    init(filename: String = "progress.json") {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory

        let directory = base.appendingPathComponent("DriveQuiz", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        self.url = directory.appendingPathComponent(filename)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> PlayerProgress {
        if let cached { return cached }

        guard FileManager.default.fileExists(atPath: url.path) else {
            lastLoadFailed = false
            cached = .fresh
            return .fresh
        }

        do {
            let data = try Data(contentsOf: url)
            let progress = try decoder.decode(PlayerProgress.self, from: data)
            lastLoadFailed = false
            cached = progress
            return progress
        } catch {
            // Corrupt or from an incompatible version. Start over rather than
            // block the drive, and keep the bad file for diagnosis.
            lastLoadFailed = true
            try? FileManager.default.moveItem(
                at: url,
                to: url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            )
            cached = .fresh
            return .fresh
        }
    }

    func save(_ progress: PlayerProgress) {
        cached = progress
        do {
            let data = try encoder.encode(progress)
            // Atomic, so a crash mid-write cannot leave a truncated file.
            try data.write(to: url, options: [.atomic])
        } catch {
            // Nothing useful to do mid-drive. The in-memory cache still holds
            // this session, and the next save will try again.
        }
    }
}
