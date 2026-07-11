import Foundation

enum SessionMode: String, CaseIterable, Identifiable {
    case lite = "Lite"
    case pro2D = "Pro 2D"

    var id: String { rawValue }
}
