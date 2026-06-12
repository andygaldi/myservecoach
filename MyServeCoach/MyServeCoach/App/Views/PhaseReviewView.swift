import AVFoundation
import AVKit
import CoreMedia
import SwiftUI

struct PhaseReviewView: View {
    let viewModel: PhaseReviewViewModel
    let onDone: ([PhaseFrame]) -> Void
    let onCancel: () -> Void

    @State private var currentTime: CMTime = .zero
    @State private var player: AVPlayer?
    @State private var navigateToPhase8 = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            thumbnailArea
            playerArea
            Spacer(minLength: 0)
            bottomToolbar
        }
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
            }
        }
        .navigationDestination(isPresented: $navigateToPhase8) {
            ReferenceFrameFetchView(confirmedFrames: viewModel.confirmedPhaseFrames())
        }
        .task(id: viewModel.currentStepIndex) {
            await setupOrSeek()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 4) {
            Text(viewModel.currentPhase.rawValue)
                .font(.title2.weight(.bold))
            Text("Step \(viewModel.currentStepIndex + 1) of \(ServePhase.allCases.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if viewModel.allPhasesAreFallback {
                Text("No pose detected — pick manually")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 12)
    }

    private var thumbnailArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(height: 100)
            if let thumb = viewModel.confirmedThumbnails[viewModel.currentPhase] {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 100)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var playerArea: some View {
        if let player {
            VideoPlayerView(player: player, currentTime: $currentTime)
                .frame(maxHeight: 300)
        }
    }

    private var bottomToolbar: some View {
        HStack {
            Button {
                if viewModel.currentStepIndex == 0 {
                    onCancel()
                    dismiss()
                } else {
                    viewModel.retreat()
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }

            Spacer()

            Button("Use This Frame") {
                viewModel.setFrame(at: currentTime)
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            if viewModel.currentStepIndex < ServePhase.allCases.count - 1 {
                Button {
                    viewModel.advance()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(viewModel.confirmedTimestamps[viewModel.currentPhase] == nil)
            } else {
                Button("Done") {
                    onDone(viewModel.confirmedPhaseFrames())
                    navigateToPhase8 = true
                }
                .disabled(!viewModel.isDoneEnabled)
            }
        }
        .padding()
    }

    // MARK: - Player

    private func setupOrSeek() async {
        if player == nil {
            player = AVPlayer(playerItem: AVPlayerItem(asset: viewModel.videoAsset))
        }
        let seekTime = viewModel.initialSeekTime(for: viewModel.currentPhase)
        let tolerance = CMTime(value: 1, timescale: 10)
        await player?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: tolerance)
        guard !Task.isCancelled else { return }
    }
}
