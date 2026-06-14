import SwiftUI

struct ComparisonView: View {
    let confirmedFrames: [PhaseFrame]
    let referenceLibrary: ReferenceFrameLibrary
    var onFinish: () -> Void = {}

    private let phaseOrder = ["trophy_pose", "racket_drop", "contact"]

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                ForEach(phaseOrder, id: \.self) { key in
                    ComparisonPhaseRowView(
                        phaseLabel: ServePhase(backendKey: key)?.rawValue ?? key,
                        userImage: confirmedFrames.first(where: { $0.phase.backendKey == key })?.thumbnail,
                        referenceFrames: referenceLibrary.referenceFrames[key] ?? []
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Serve Comparison")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onFinish() }
            }
        }
    }
}
