import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            VideoSourceSelectionView()
                .tabItem { Label("Record", systemImage: "camera") }
            SessionHistoryView()
                .tabItem { Label("History", systemImage: "clock") }
        }
    }
}
