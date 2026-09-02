import SwiftData
import SwiftUI

struct SetGoalRecordingView: View {
    let goal: GoalDefinition
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SetGoalSessionViewModel

    init(goal: GoalDefinition, onDone: @escaping () -> Void) {
        self.goal = goal
        self.onDone = onDone
        _viewModel = State(initialValue: SetGoalSessionViewModel(goal: goal))
    }

    var body: some View {
        #if targetEnvironment(simulator)
        SimulatorPlaceholderView()
        #else
        ZStack {
            CameraPreviewView(session: viewModel.cameraViewModel.session)
                .ignoresSafeArea()

            VStack {
                if viewModel.isRecording {
                    tallyHeader
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.white)
                        .font(.caption)
                        .padding(8)
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                recordingControls
            }
            .padding()
        }
        .task {
            await viewModel.cameraViewModel.startSession()
        }
        .onDisappear {
            viewModel.cameraViewModel.stopSession()
        }
        .sheet(isPresented: summaryPresented) {
            summarySheet
        }
        .toolbar(.hidden, for: .tabBar)
        #endif
    }

    private var tallyHeader: some View {
        Text("\(viewModel.passCount)/\(viewModel.attemptCount) passed")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var recordingControls: some View {
        Button(action: {
            if viewModel.isRecording {
                viewModel.stopSession()
            } else {
                viewModel.startSession()
            }
        }) {
            Label(
                viewModel.isRecording ? "Stop" : "Start Session",
                systemImage: viewModel.isRecording ? "stop.circle.fill" : "video.circle.fill"
            )
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(viewModel.isRecording ? Color.red : Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(viewModel.isFinalizing)
    }

    private var summaryPresented: Binding<Bool> {
        Binding(
            get: { !viewModel.isFinalizing && !viewModel.isRecording && !viewModel.attempts.isEmpty },
            set: { _ in }
        )
    }

    private var summarySheet: some View {
        NavigationStack {
            List(viewModel.attempts) { attempt in
                GoalAttemptRowView(
                    segmentIndex: attempt.segmentIndex, passed: attempt.passed, spokenCue: attempt.spokenCue
                )
            }
            .navigationTitle("Session Summary")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.persist(to: modelContext)
                        onDone()
                    }
                }
            }
        }
    }
}
