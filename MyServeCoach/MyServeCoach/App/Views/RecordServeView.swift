import SwiftUI
import SwiftData

struct RecordServeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = RecordServeViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Camera preview placeholder — replaced with AVCaptureVideoPreviewLayer in Video Capture MVP
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(Text("Camera Preview").foregroundStyle(.secondary))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(9/16, contentMode: .fit)

                if viewModel.isProcessing {
                    ProgressView("Analyzing serve…")
                } else {
                    Button(action: toggleRecording) {
                        Label(
                            viewModel.isRecording ? "Stop" : "Record Serve",
                            systemImage: viewModel.isRecording ? "stop.circle.fill" : "video.circle.fill"
                        )
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(viewModel.isRecording ? Color.red : Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }

                if let error = viewModel.recordingError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Spacer()
            }
            .navigationTitle("Record Serve")
        }
    }

    private func toggleRecording() {
        if viewModel.isRecording {
            viewModel.stopRecording(context: modelContext)
        } else {
            viewModel.startRecording()
        }
    }
}
