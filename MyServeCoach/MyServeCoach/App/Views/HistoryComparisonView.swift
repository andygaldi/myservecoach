import SwiftUI

struct HistoryComparisonView: View {
    let session: ServeSession

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                ForEach(ServePhase.allCases, id: \.self) { phase in
                    let record = session.phases.first(where: { $0.phaseKey == phase.backendKey })
                    let userImage = record.flatMap { UIImage(data: $0.frameImageData) }
                    let refFrames: [ReferenceFrame] = record?.referenceFrameURLs.compactMap { urlStr in
                        guard let url = URL(string: urlStr) else { return nil }
                        return ReferenceFrame(phase: phase, label: record?.label ?? phase.rawValue, imageURL: url)
                    } ?? []
                    ComparisonPhaseRowView(
                        phaseLabel: phase.rawValue,
                        userImage: userImage,
                        referenceFrames: refFrames
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Serve Comparison")
        .navigationBarTitleDisplayMode(.inline)
    }
}
