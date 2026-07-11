import Foundation
import Testing
@testable import MyServeCoach

@Suite("MultipartFormEncoder Tests")
struct MultipartFormEncoderTests {

    private func partsString(_ data: Data, boundary: String) -> [String] {
        let raw = String(decoding: data, as: UTF8.self)
        return raw.components(separatedBy: "--\(boundary)")
    }

    @Test("encodes exactly one frames file part per frame, with correct filename and content type")
    func encodesFileParts() {
        let encoder = MultipartFormEncoder()
        let jpeg0 = Data([0xFF, 0xD8, 0xFF, 0x00])
        let jpeg1 = Data([0xFF, 0xD8, 0xFF, 0x01])
        let body = encoder.encodeFrames(
            [(timestamp: 0.1, jpegData: jpeg0), (timestamp: 0.5, jpegData: jpeg1)],
            sessionId: nil
        )
        let raw = String(decoding: body, as: UTF8.self)

        #expect(raw.contains("name=\"frames\"; filename=\"frame0.jpg\""))
        #expect(raw.contains("name=\"frames\"; filename=\"frame1.jpg\""))
        #expect(raw.contains("Content-Type: image/jpeg"))
        #expect(body.range(of: jpeg0) != nil)
        #expect(body.range(of: jpeg1) != nil)
    }

    @Test("encodes exactly one timestamps text part per frame, not a JSON array")
    func encodesTimestampParts() {
        let encoder = MultipartFormEncoder()
        let body = encoder.encodeFrames(
            [(timestamp: 0.1, jpegData: Data()), (timestamp: 0.5, jpegData: Data())],
            sessionId: nil
        )
        let raw = String(decoding: body, as: UTF8.self)
        let timestampPartCount = raw.components(separatedBy: "name=\"timestamps\"").count - 1

        #expect(timestampPartCount == 2)
        #expect(raw.contains("name=\"timestamps\"\r\n\r\n0.1"))
        #expect(raw.contains("name=\"timestamps\"\r\n\r\n0.5"))
        #expect(!raw.contains("[0.1"))
    }

    @Test("includes a session_id part only when non-nil")
    func sessionIdPartPresenceMatchesInput() {
        let encoder = MultipartFormEncoder()
        let withSession = encoder.encodeFrames([(timestamp: 0.1, jpegData: Data())], sessionId: "abc-123")
        let withoutSession = encoder.encodeFrames([(timestamp: 0.1, jpegData: Data())], sessionId: nil)

        #expect(String(decoding: withSession, as: UTF8.self).contains("name=\"session_id\"\r\n\r\nabc-123"))
        #expect(!String(decoding: withoutSession, as: UTF8.self).contains("name=\"session_id\""))
    }

    @Test("body ends with the closing boundary delimiter")
    func endsWithClosingBoundary() {
        let encoder = MultipartFormEncoder()
        let body = encoder.encodeFrames([(timestamp: 0.1, jpegData: Data())], sessionId: nil)
        let raw = String(decoding: body, as: UTF8.self)

        #expect(raw.hasSuffix("--\(encoder.boundary)--\r\n"))
    }

    @Test("contentType header matches the generated boundary")
    func contentTypeMatchesBoundary() {
        let encoder = MultipartFormEncoder()
        #expect(encoder.contentType == "multipart/form-data; boundary=\(encoder.boundary)")
    }
}
