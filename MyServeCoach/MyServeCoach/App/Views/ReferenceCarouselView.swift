import SwiftUI

struct ReferenceCarouselView: View {
    let frames: [ReferenceFrame]

    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                AsyncImage(url: frame.imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Rectangle().fill(Color(.systemGray5))
                    case .empty:
                        ProgressView()
                    @unknown default:
                        Rectangle().fill(Color(.systemGray5))
                    }
                }
                .clipped()
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: frames.count == 1 ? .never : .automatic))
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipped()
    }
}
