import Foundation

final class ReferenceFrameService {
    private let baseURL: URL

    init(baseURL: URL = BackendConfig.baseURL) {
        self.baseURL = baseURL
    }

    func fetchReferenceFrames() async throws -> ReferenceFrameLibrary {
        let url = baseURL.appendingPathComponent("reference-frames")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ReferenceFrameLibrary.self, from: data)
    }
}
