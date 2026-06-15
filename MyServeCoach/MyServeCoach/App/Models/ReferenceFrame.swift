import Foundation

struct ReferenceFrame: Codable {
    let phase: ServePhase
    let label: String
    let imageURL: URL

    init(phase: ServePhase, label: String, imageURL: URL) {
        self.phase = phase
        self.label = label
        self.imageURL = imageURL
    }

    enum CodingKeys: String, CodingKey {
        case phase, label
        case imageURL = "image_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let key = try c.decode(String.self, forKey: .phase)
        guard let resolved = ServePhase(backendKey: key) else {
            throw DecodingError.dataCorruptedError(forKey: .phase, in: c, debugDescription: "Unknown phase key: \(key)")
        }
        phase = resolved
        label = try c.decode(String.self, forKey: .label)
        imageURL = try c.decode(URL.self, forKey: .imageURL)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(phase.backendKey, forKey: .phase)
        try c.encode(label, forKey: .label)
        try c.encode(imageURL, forKey: .imageURL)
    }
}

struct ReferenceFrameLibrary: Codable {
    let referenceFrames: [String: [ReferenceFrame]]

    enum CodingKeys: String, CodingKey {
        case referenceFrames = "reference_frames"
    }
}
