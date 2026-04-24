import SwiftUI

struct RecordServeView: View {
    var onClipSelected: (URL) -> Void = { _ in }

    @Environment(\.openURL) private var openURL
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

                if cameraViewModel.permissionDenied {
                    permissionDeniedBanner
                }

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

    private var permissionDeniedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.fill")
            Text("Camera access denied.")
                .font(.subheadline)
            Spacer()
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding()
        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
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
