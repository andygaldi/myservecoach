import SwiftData
import SwiftUI

struct ComparisonView: View {
    let confirmedFrames: [PhaseFrame]
    let referenceLibrary: ReferenceFrameLibrary
    var inputType: String = "imported"
    var videoURL: URL? = nil
    var onFinish: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @State private var alreadySaved = false

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
        .onAppear {
            guard !alreadySaved else { return }
            alreadySaved = true
            SessionPersistenceService().save(
                confirmedFrames: confirmedFrames,
                referenceLibrary: referenceLibrary,
                inputType: inputType,
                videoURL: videoURL,
                into: modelContext
            )
        }
    }
}
