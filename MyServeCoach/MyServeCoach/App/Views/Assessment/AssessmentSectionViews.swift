import SwiftUI

/// Shared assessment layout, used by both `AssessmentResultView` (live) and
/// `AssessmentHistoryDetailView` (replay) so the two can't drift apart.

struct AssessmentHeaderView: View {
    let serveCount: Int
    let majorCount: Int
    let minorCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(serveCount) serve\(serveCount == 1 ? "" : "s") analyzed")
                .font(.title2.weight(.bold))
            Text("\(majorCount) major · \(minorCount) minor")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct AssessmentAggregateSection: View {
    let rows: [AssessmentAggregateRow]

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Most frequent")
                    .font(.headline)
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        SeverityDot(severity: row.severity)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.message)
                                .font(.subheadline)
                            Text(row.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct AssessmentServeSectionView: View {
    let section: AssessmentServeSectionDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.headline)

            if section.hasNoCues, let summary = section.summary {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }

            ForEach(section.phaseFrames) { phaseFrame in
                PhaseFrameBlockView(phaseFrame: phaseFrame)
            }

            ForEach(section.unpairedCues) { cue in
                CueRowView(cue: cue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PhaseFrameBlockView: View {
    let phaseFrame: AssessmentPhaseFrameDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(phaseFrame.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            PhaseFrameOverlayView(
                image: phaseFrame.image,
                frame: phaseFrame.frame,
                detections: phaseFrame.detections,
                highlightedCue: phaseFrame.highlightedCue
            )
            .accessibilityLabel("\(phaseFrame.label) frame with pose overlay")

            ForEach(phaseFrame.cues) { cue in
                CueRowView(cue: cue)
            }
        }
    }
}

struct CueRowView: View {
    let cue: AssessmentCueDisplay

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SeverityDot(severity: cue.severity)
            VStack(alignment: .leading, spacing: 2) {
                Text(cue.message)
                    .font(.subheadline)
                if let caption = cue.deviationCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SeverityDot: View {
    let severity: String

    var body: some View {
        Circle()
            .fill(Color(severity: severity))
            .frame(width: 8, height: 8)
            .padding(.top, 6)
    }
}

extension Color {
    /// The single severity→colour mapping, shared by the cue rows and the overlay's highlight.
    /// Defined once because the two previously disagreed on the fallback for an unrecognized
    /// severity — harmless on today's data, exactly the kind of thing that drifts later.
    init(severity: String) {
        self = severity == "minor" ? .orange : .red
    }
}
