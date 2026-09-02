import Foundation

/// Intercepts requests made on a `URLSession` configured with this protocol class, returning a
/// canned response/data/error and capturing the request body for assertion.
///
/// State is keyed by request host, not a single global "last request" — the URL Loading System
/// owns `URLProtocol` instantiation and Swift Testing runs test functions concurrently by
/// default, so two tests' network calls can genuinely overlap in time. Give each test a unique
/// host (see `StubURLProtocol.uniqueBaseURL()`) and this stays correct under any concurrency.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let statusCode: Int
        let data: Data
        let error: Error?

        init(statusCode: Int = 200, data: Data = Data(), error: Error? = nil) {
            self.statusCode = statusCode
            self.data = data
            self.error = error
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubsByHost: [String: Stub] = [:]
    nonisolated(unsafe) private static var lastBodyByHost: [String: Data] = [:]
    nonisolated(unsafe) private static var lastURLByHost: [String: URL] = [:]

    /// A `http://<unique-host>.test/` base URL — pass to the service under test so its requests
    /// don't collide with any other concurrently-running test's stubbed state.
    static func uniqueBaseURL() -> URL {
        URL(string: "http://\(UUID().uuidString).test")!
    }

    static func setStub(_ stub: Stub, for baseURL: URL) {
        guard let host = baseURL.host else { return }
        lock.withLock { stubsByHost[host] = stub }
    }

    static func lastBody(for baseURL: URL) -> Data? {
        guard let host = baseURL.host else { return nil }
        return lock.withLock { lastBodyByHost[host] }
    }

    static func lastURL(for baseURL: URL) -> URL? {
        guard let host = baseURL.host else { return nil }
        return lock.withLock { lastURLByHost[host] }
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let stub = Self.lock.withLock {
            Self.lastBodyByHost[host] = request.httpBodyStreamData() ?? request.httpBody
            Self.lastURLByHost[host] = request.url
            return Self.stubsByHost[host] ?? Stub()
        }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private extension URLRequest {
    func httpBodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
