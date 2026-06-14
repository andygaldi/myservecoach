import SwiftUI

struct ComparisonView: View {
    let confirmedFrames: [PhaseFrame]
    let referenceLibrary: ReferenceFrameLibrary
    var onFinish: () -> Void = {}

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                ForEach(ServePhase.allCases, id: \.self) { phase in
                    ComparisonPhaseRowView(
                        phaseLabel: phase.rawValue,
                        userImage: confirmedFrames.first(where: { $0.phase == phase })?.thumbnail,
                        referenceFrames: referenceLibrary.referenceFrames[phase.backendKey] ?? []
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Serve Comparison")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onFinish() }
            }
        }
    }
}
