import CoreMedia
import SwiftUI

struct ReferenceFrameFetchView: View {
    let confirmedFrames: [PhaseFrame]

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("Reference Frame Fetch")
                .font(.title2.weight(.bold))
            Text("Phase 8 — Coming soon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider()
                .padding(.horizontal)
            ForEach(confirmedFrames, id: \.phase.rawValue) { frame in
                HStack {
                    Text(frame.phase.rawValue)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.2fs", frame.timestamp.seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            Spacer()
        }
        .navigationTitle("Reference Frames")
        .navigationBarTitleDisplayMode(.inline)
    }
}
