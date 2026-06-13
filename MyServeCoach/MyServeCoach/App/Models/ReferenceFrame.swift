import Foundation

struct ReferenceFrame: Codable {
    let phase: String
    let label: String
    let imageURL: URL

    enum CodingKeys: String, CodingKey {
        case phase, label
        case imageURL = "image_url"
    }
}

struct ReferenceFrameLibrary: Codable {
    let referenceFrames: [String: ReferenceFrame]

    enum CodingKeys: String, CodingKey {
        case referenceFrames = "reference_frames"
    }
}
