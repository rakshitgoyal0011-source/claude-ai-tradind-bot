import Foundation
import DriveQuizKit

enum PackLoaderError: Error {
    case notFound(String)
    case malformed(String, underlying: Error)
    case noPacksAvailable
}

enum PackLoader {

    /// Explicit rather than enumerating the bundle, so a stray JSON resource
    /// can never turn into a question pack.
    static let bundledPackNames = [
        "starter-20",
        "science-20",
        "history-20",
        "culture-20",
        "world-20"
    ]

    static func load(_ name: String, in bundle: Bundle = .main) throws -> QuestionPack {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw PackLoaderError.notFound(name)
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(QuestionPack.self, from: data)
        } catch {
            throw PackLoaderError.malformed(name, underlying: error)
        }
    }

    /// Loads every bundled pack, skipping any that fail rather than refusing
    /// to start. One bad pack should cost the driver that theme, not the drive.
    static func loadAll(in bundle: Bundle = .main) throws -> [QuestionPack] {
        var packs: [QuestionPack] = []

        for name in bundledPackNames {
            do {
                packs.append(try load(name, in: bundle))
            } catch {
                assertionFailure("pack \(name) failed to load: \(error)")
            }
        }

        guard !packs.isEmpty else { throw PackLoaderError.noPacksAvailable }
        return packs
    }
}
