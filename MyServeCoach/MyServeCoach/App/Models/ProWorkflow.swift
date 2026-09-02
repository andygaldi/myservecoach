import Foundation

enum ProWorkflow: String, CaseIterable, Identifiable {
    case assessment = "Assessment"
    case setGoal = "Set Goal"
    var id: String { rawValue }
}
