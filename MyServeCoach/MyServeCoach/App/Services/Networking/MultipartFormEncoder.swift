import Foundation

/// Builds `multipart/form-data` bodies matching FastAPI's `File(...)`/`Form(...)` expectations:
/// repeated `frames` file parts (one per JPEG) and repeated `timestamps` text parts (one per
/// value, not a JSON array) — see backend/tests/test_pose_endpoint.py for the wire contract.
struct MultipartFormEncoder {
    let boundary = "Boundary-\(UUID().uuidString)"

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    func encodeFrames(_ frames: [(timestamp: Double, jpegData: Data)], sessionId: String?) -> Data {
        var body = Data()
        for (index, frame) in frames.enumerated() {
            appendFilePart(
                to: &body, name: "frames", filename: "frame\(index).jpg",
                mimeType: "image/jpeg", fileData: frame.jpegData
            )
        }
        for frame in frames {
            appendTextPart(to: &body, name: "timestamps", value: String(frame.timestamp))
        }
        if let sessionId {
            appendTextPart(to: &body, name: "session_id", value: sessionId)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func appendFilePart(
        to body: inout Data, name: String, filename: String, mimeType: String, fileData: Data
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
    }

    private func appendTextPart(to body: inout Data, name: String, value: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }
}
