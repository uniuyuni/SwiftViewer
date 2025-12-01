import SwiftUI

struct AsyncThumbnailView: View {
    let url: URL
    let size: CGSize
    var id: UUID? = nil // Optional ID for cache lookup
    var orientation: Int? = nil // Added
    
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var loadedOrientation: Int? = nil
    
    @State private var debugOrientation: Int?
    @State private var rotationAngle: Angle = .zero
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(rotationAngle)
            } else {
                Color.gray.opacity(0.1)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            
            // Debug Overlay Removed
        }
        .frame(width: size.width, height: size.height)
        // Update task identity to include orientation so we reload/re-rotate if it changes
        .task(id: "\(url.path)_\(orientation ?? -1)") {
            await loadThumbnail()
        }
    }
    
    private func angleForOrientation(_ orientation: Int?) -> Angle {
        guard let orientation = orientation else { return .zero }
        
        // Only apply manual rotation for RAW files
        // Standard files (JPG, HEIC) are handled by ThumbnailGenerator (CGImageSource) which applies transform.
        let ext = url.pathExtension.lowercased()
        let isRaw = FileConstants.allowedImageExtensions.contains(ext) && !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)
        
        guard isRaw else { return .zero }
        
        switch orientation {
        case 3, 4: return .degrees(180)
        case 6, 5: return .degrees(90)
        case 8, 7: return .degrees(-90)
        default: return .zero
        }
    }
    
    private func loadThumbnail() async {
        // 1. Fast Path: Memory Cache (Main Thread)
        // If we have an ID and it's in memory, show immediately.
        if let id = id, let cached = ThumbnailCacheService.shared.loadFromMemory(for: id) {
             self.image = cached
             self.isLoading = false
             // If orientation is provided, apply it.
             // If not, we might be missing rotation for RAWs, but it's better than waiting.
             // The background task can still run to refine it? No, that defeats the purpose.
             // For Catalog items, orientation is usually known.
             if let o = orientation {
                 self.rotationAngle = self.angleForOrientation(o)
             }
             return
        }
        
        isLoading = true
        
        let currentID = id
        let currentURL = url
        let inputOrientation = orientation
        let targetSize = size
        
        // Offload disk I/O and generation to background
        let result = await Task.detached(priority: .userInitiated) { () -> (NSImage?, Int?) in
            // Resolve orientation
            var resolvedOrientation = inputOrientation
            if resolvedOrientation == nil {
                let ext = currentURL.pathExtension.lowercased()
                let isRaw = !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)
                if isRaw {
                    resolvedOrientation = await ExifReader.shared.readOrientation(from: currentURL)
                }
            }
            
            // 1. Try Cache
            if let id = currentID, let cached = ThumbnailCacheService.shared.loadThumbnail(for: id) {
                return (cached, resolvedOrientation)
            }
            
            // 2. Generate
            let thumb = await ThumbnailGenerator.shared.generateThumbnail(for: currentURL, size: targetSize, orientation: resolvedOrientation)
            
            // Cache if we have an ID
            if let id = currentID, let generated = thumb {
                ThumbnailCacheService.shared.saveThumbnail(image: generated, for: id)
            }
            
            return (thumb, resolvedOrientation)
        }.value
        
        // Update UI on Main Actor
        self.image = result.0
        self.loadedOrientation = result.1
        self.rotationAngle = self.angleForOrientation(self.loadedOrientation ?? self.orientation)
        self.isLoading = false
    }
}
