import Foundation
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

struct LibraryVideoExporter {
    func export(_ item: PhotosPickerItem) async throws -> URL {
        guard let movie = try await item.loadTransferable(type: LibraryMovie.self) else {
            throw ExportError.loadFailed
        }
        return movie.url
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
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}
