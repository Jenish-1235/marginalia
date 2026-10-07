import SwiftUI
import UIKit

nonisolated final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    // NSCache is thread-safe.
    private let cache = NSCache<NSString, UIImage>()

    @concurrent
    func image(for documentID: String) async -> UIImage? {
        if let cached = cache.object(forKey: documentID as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: FileStore.thumbnailURL(for: documentID).path) else { return nil }
        let decoded = image.preparingForDisplay() ?? image
        cache.setObject(decoded, forKey: documentID as NSString)
        return decoded
    }

    func remove(_ documentID: String) {
        cache.removeObject(forKey: documentID as NSString)
    }
}

struct ThumbnailView: View {
    let documentID: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Theme.elevated)
                    .aspectRatio(0.75, contentMode: .fit)
            }
        }
        .task(id: documentID) {
            image = await ThumbnailCache.shared.image(for: documentID)
        }
    }
}
