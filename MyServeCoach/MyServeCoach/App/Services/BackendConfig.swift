import Foundation

enum BackendConfig {
    // Both simulator (macOS 15+ virtualizes loopback) and physical device
    // require the Mac's LAN IP to reach the local dev server.
    static let baseURL = URL(string: "http://192.168.86.205:8000")!
}
