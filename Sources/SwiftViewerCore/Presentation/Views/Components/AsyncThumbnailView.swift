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
        .task(id: url) {
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
        case 6, 5: return .degrees(90) // 6 is Right-Top (Rotated 90 CW). Rotate 90 to upright? No, if it's 90 CW, we need -90 to undo?
                                       // Wait, user said "Rotation direction is reversed".
                                       // Previous code was: case 6, 5: return .degrees(-90)
                                       // So I should change it to 90.
        case 8, 7: return .degrees(-90)  // 8 is Left-Bottom (Rotated 270 CW). Rotate -90 (or 270) to upright?
                                         // Previous code was: case 8, 7: return .degrees(90)
                                         // So I should change it to -90.
        default: return .zero
        }
    }
    
    private func loadThumbnail() async {
        isLoading = true
        
        // Load orientation if needed (for Copy Mode where it might be nil)
        var currentOrientation = orientation
        if currentOrientation == nil {
            let ext = url.pathExtension.lowercased()
            let isRaw = !["jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"].contains(ext)
            if isRaw {
                // Read orientation from file (Fast path)
                currentOrientation = await ExifReader.shared.readOrientation(from: url)
            }
        }
        
        // 1. Try Cache if ID is present
        if let id = id, let cached = ThumbnailCacheService.shared.loadThumbnail(for: id) {
             await MainActor.run {
                 self.image = cached
                 self.isLoading = false
             }
             return
        }
        
        // 2. Try Generator (File System)
        let thumb = await ThumbnailGenerator.shared.generateThumbnail(for: url, size: size, orientation: currentOrientation)
        
        // 3. If Generator succeeded, and we have an ID, cache it?
        // MediaRepository does caching on import.
        // But if we are in Folder mode (no ID usually, unless we pass random UUID), we don't cache persistently?
        // Correct. Persistent cache is for Catalog items.
        
        await MainActor.run {
            self.image = thumb
            self.isLoading = false
            if self.loadedOrientation == nil {
                self.loadedOrientation = currentOrientation
            }
            self.rotationAngle = self.angleForOrientation(self.loadedOrientation ?? self.orientation)
        }
    }
}
