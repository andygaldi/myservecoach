import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LibraryVideoExporter {
    func export(_ item: PhotosPickerItem) async throws -> URL {
        guard let movie = try await item.loadTransferable(type: LibraryMovie.self) else {
            throw ExportError.loadFailed
        }
        return movie.url
    }

    /// Copies `source` to a new .mov file in the temp directory.
    /// Extracted so tests can verify the copy logic without a PhotosPickerItem.
    nonisolated static func copyToTemp(from source: URL) throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    enum ExportError: LocalizedError {
        case loadFailed

        var errorDescription: String? { "Could not load video from Photos library." }
    }
}

// Copies the selected video into the app's temp directory as a .mov file.
private struct LibraryMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = try LibraryVideoExporter.copyToTemp(from: received.file)
            return Self(url: dest)
        }
    }
}
