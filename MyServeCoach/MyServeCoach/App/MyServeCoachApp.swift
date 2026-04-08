import SwiftUI
import SwiftData

@main
struct MyServeCoachApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Serve.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
