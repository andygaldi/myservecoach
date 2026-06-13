import Foundation

final class ReferenceFrameService {
    private let baseURL: URL

    init(baseURL: URL = BackendConfig.baseURL) {
        self.baseURL = baseURL
    }

    func fetchReferenceFrames() async throws -> ReferenceFrameLibrary {
        let url = baseURL.appendingPathComponent("reference-frames")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(ReferenceFrameLibrary.self, from: data)
    }
}
