import SwiftUI

struct ContentView: View {
    @State private var videoSelectionVM = VideoSourceSelectionViewModel()

    var body: some View {
        TabView {
            VideoSourceSelectionView(viewModel: videoSelectionVM)
                .tabItem { Label("Record", systemImage: "camera") }
            SessionHistoryView()
                .tabItem { Label("History", systemImage: "clock") }
        }
        .overlay {
            if videoSelectionVM.noPoseDetected {
                ErrorView(
                    systemImage: "figure.stand",
                    title: "No Pose Detected",
                    message: "Make sure your full body is visible in the frame and the lighting is adequate.",
                    primaryActionLabel: "Try Again",
                    primaryAction: {
                        videoSelectionVM.noPoseDetected = false
                        videoSelectionVM.errorMessage = nil
                    }
                )
            }
        }
        .overlay {
            if videoSelectionVM.isProcessing {
                LoadingOverlayView(message: "Analyzing pose…")
            }
        }
    }
}
