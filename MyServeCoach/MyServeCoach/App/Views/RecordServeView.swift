import SwiftUI

struct RecordServeView: View {
    var onClipSelected: (URL) -> Void = { _ in }

    @State private var cameraViewModel = CameraViewModel()

    var body: some View {
        #if targetEnvironment(simulator)
        SimulatorPlaceholderView()
        #else
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
        .sheet(isPresented: Binding(
            get: { cameraViewModel.previewURL != nil },
            set: { isShowing in
                if !isShowing, let url = cameraViewModel.previewURL {
                    cameraViewModel.retake(url: url)
                }
            }
        )) {
            if let url = cameraViewModel.previewURL {
                ClipPreviewView(
                    url: url,
                    onUseClip: {
                        cameraViewModel.useClip()
                        onClipSelected(url)
                    },
                    onRetake: {
                        cameraViewModel.retake(url: url)
                    }
                )
            }
        }
        #endif
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
            EmptyView()
        }
    }
}
