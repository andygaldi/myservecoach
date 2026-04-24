import SwiftUI

struct RecordServeView: View {
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

                recordingControls
            }
        }
        .task {
            await cameraViewModel.startSession()
        }
        .onDisappear {
            cameraViewModel.stopSession()
        }
    }

    @ViewBuilder
    private var recordingControls: some View {
        switch cameraViewModel.recordingState {
        case .idle, .recording:
            VStack(spacing: 8) {
                Button(action: { cameraViewModel.toggleRecording() }) {
                    Label(
                        cameraViewModel.isRecording ? "Stop" : "Record Serve",
                        systemImage: cameraViewModel.isRecording ? "stop.circle.fill" : "video.circle.fill"
                    )
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(cameraViewModel.isRecording ? Color.red : Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                if let error = cameraViewModel.recordingError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding(.bottom)

        case .previewing:
            EmptyView() // replaced by VideoPlayer sheet in Group 3
        }
    }
}
