import UIKit

/// Downscales and JPEG-encodes an extracted phase frame for persistence.
///
/// Four frames are retained per serve, so a multi-serve session stores a couple of dozen images
/// in SwiftData. 720px on the long edge is comfortably above the display size on any iPhone
/// while keeping a typical session's imagery in the low single-digit MB.
enum PhaseFrameImageEncoder {
    static let maxLongEdge: CGFloat = 720
    static let jpegQuality: CGFloat = 0.7

    /// Returns JPEG data for `image`, downscaled so its long edge is at most `maxLongEdge`.
    /// A source already at or below that size is encoded at its original dimensions — never
    /// upscaled. Returns `nil` only if JPEG encoding itself fails.
    static func encode(_ image: UIImage) -> Data? {
        scaled(image).jpegData(compressionQuality: jpegQuality)
    }

    /// Exposed for testing the scaling rule independently of JPEG encoding.
    static func scaled(_ image: UIImage) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxLongEdge else { return image }

        let ratio = maxLongEdge / longEdge
        let target = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
