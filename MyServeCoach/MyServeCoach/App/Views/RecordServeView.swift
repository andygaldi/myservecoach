import SwiftUI
import SwiftData

struct RecordServeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = RecordServeViewModel()
    @State private var cameraViewModel = CameraViewModel()

    var body: some View {
        ZStack {
            CameraPreviewView(session: cameraViewModel.session)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(action: { cameraViewModel.toggleCamera() }) {
                        Image(systemName: "camera.rotate")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .disabled(cameraViewModel.isRecording)
                }
                .padding()

                Spacer()

                if viewModel.isProcessing {
                    ProgressView("Analyzing serve…")
                        .foregroundStyle(.white)
                        .padding(.bottom)
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
                    .padding(.bottom)
                }

                if let error = viewModel.recordingError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.bottom)
                }
            }
        }
        .task {
            await cameraViewModel.startSession()
        }
        .onDisappear {
            cameraViewModel.stopSession()
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
