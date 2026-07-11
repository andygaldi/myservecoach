import Foundation

struct BackendBoundingBox: Codable, Sendable, Equatable {
    let xMin: Float
    let yMin: Float
    let xMax: Float
    let yMax: Float

    enum CodingKeys: String, CodingKey {
        case xMin = "x_min", yMin = "y_min", xMax = "x_max", yMax = "y_max"
    }
}

struct BackendDetection: Codable, Sendable, Equatable {
    let label: String
    let confidence: Float
    let bbox: BackendBoundingBox
}
