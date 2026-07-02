import Foundation

struct BackendKeypoint: Codable, Sendable {
    let x: Float
    let y: Float
    let confidence: Float
}

struct BackendFrame: Codable, Sendable {
    let timestamp: Double
    let keypoints: [String: BackendKeypoint]
}
