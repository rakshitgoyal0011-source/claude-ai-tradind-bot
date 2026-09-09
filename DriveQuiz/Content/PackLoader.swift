import Foundation
import DriveQuizKit

enum PackLoaderError: Error {
    case notFound(String)
    case malformed(String, underlying: Error)
}

enum PackLoader {

    /// Phase 1 ships one static pack. No network, no runtime generation.
    static func load(_ name: String = "starter-20", in bundle: Bundle = .main) throws -> QuestionPack {
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
}
