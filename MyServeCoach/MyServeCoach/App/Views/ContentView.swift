import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RecordServeView()
                .tabItem {
                    Label("Record", systemImage: "video.circle")
                }

            ResultsView()
                .tabItem {
                    Label("Results", systemImage: "list.bullet.clipboard")
                }
        }
    }
}
