import SwiftUI
import CoreData

struct DetailView: View {
    @ObservedObject var viewModel: MainViewModel
    
    // Helper to find the MediaItem corresponding to the selected FileItem
    private var selectedMediaItem: MediaItem? {
        guard let currentFile = viewModel.currentFile, viewModel.appMode == .catalog else { return nil }
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "originalPath == %@", currentFile.url.path)
        request.fetchLimit = 1
        return try? PersistenceController.shared.container.viewContext.fetch(request).first
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Main Content (Image/Video)
            ZStack {
                Color(nsColor: .windowBackgroundColor) // Background
                
                if viewModel.selectedFiles.count > 1 {
                    // Multi-selection state
                    VStack {
                        Image(systemName: "square.stack.3d.down.right")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.selectedFiles.count) items selected")
                            .font(.title2)
                            .padding()
                    }
                } else if let item = viewModel.currentFile {
                    if FileConstants.allowedVideoExtensions.contains(item.url.pathExtension.lowercased()) {
                        VideoPlayerView(url: item.url)
                    } else {
                        ZoomableImageView(url: item.url, itemID: item.uuid)
                    }
                } else {
                    if #available(macOS 14.0, *) {
                        ContentUnavailableView {
                            Label("No Selection", systemImage: "photo.badge.plus")
                        } description: {
                            Text("Select an item from the grid to view details.")
                        }
                    } else {
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Select an item from the grid to view details.")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 100)
        // Hidden button for Space key shortcut
        .background {
            Button("") {
                let urls: [URL]
                if !viewModel.selectedFiles.isEmpty {
                    urls = viewModel.selectedFiles.map { $0.url }
                } else if let item = viewModel.currentFile {
                    urls = [item.url]
                } else {
                    urls = []
                }
                
                if !urls.isEmpty {
                    QuickLookService.shared.toggleQuickLook(for: urls)
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
        }
    }

    private func colorFromString(_ name: String) -> Color {
        switch name {
        case "Red": return .red
        case "Yellow": return .yellow
        case "Green": return .green
        case "Blue": return .blue
        case "Purple": return .purple
        default: return .gray
        }
    }
}

struct ZoomableImageView: View {
    let url: URL
    let itemID: UUID? // Add ID for cache lookup
    
    @State private var image: NSImage?
    @State private var isZoomed: Bool = false
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isOffline: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let nsImage = image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: isZoomed ? .fill : .fit)
                        .frame(
                            width: isZoomed ? nsImage.size.width : geometry.size.width,
                            height: isZoomed ? nsImage.size.height : geometry.size.height
                        )
                        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
                        .gesture(
                            isZoomed ?
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    let maxOffsetX = max(0, (nsImage.size.width - geometry.size.width) / 2)
                                    let maxOffsetY = max(0, (nsImage.size.height - geometry.size.height) / 2)
                                    
                                    var newX = offset.width + value.translation.width
                                    var newY = offset.height + value.translation.height
                                    
                                    // Clamp
                                    if newX > maxOffsetX { newX = maxOffsetX }
                                    if newX < -maxOffsetX { newX = -maxOffsetX }
                                    if newY > maxOffsetY { newY = maxOffsetY }
                                    if newY < -maxOffsetY { newY = -maxOffsetY }
                                    
                                    withAnimation {
                                        offset = CGSize(width: newX, height: newY)
                                        dragOffset = .zero
                                    }
                                }
                            : nil
                        )
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { event in
                                    let location = event.location
                                    
                                    withAnimation {
                                        if isZoomed {
                                            // Zoom out to fit
                                            isZoomed = false
                                            offset = .zero
                                            dragOffset = .zero
                                        } else {
                                            // Zoom in to click point
                                            isZoomed = true
                                            
                                            // Calculate offset to center the clicked point
                                            // 1. Get relative position in the FIT view
                                            // The image is aspect fit, so it might have letterboxing/pillarboxing.
                                            // But for simplicity, let's assume the tap is within the image bounds (or close enough).
                                            // Actually, if aspect ratio differs, we need to account for empty space.
                                            
                                            let viewSize = geometry.size
                                            let imageSize = nsImage.size
                                            
                                            let widthRatio = viewSize.width / imageSize.width
                                            let heightRatio = viewSize.height / imageSize.height
                                            let scale = min(widthRatio, heightRatio)
                                            
                                            let displayWidth = imageSize.width * scale
                                            let displayHeight = imageSize.height * scale
                                            
                                            let xPadding = (viewSize.width - displayWidth) / 2
                                            let yPadding = (viewSize.height - displayHeight) / 2
                                            
                                            // Relative position within the image (0.0 to 1.0)
                                            let relativeX = (location.x - xPadding) / displayWidth
                                            let relativeY = (location.y - yPadding) / displayHeight
                                            
                                            // Target point in FULL size image
                                            let targetX = relativeX * imageSize.width
                                            let targetY = relativeY * imageSize.height
                                            
                                            // Calculate offset to bring targetX, targetY to center of view
                                            // Center of view is viewSize / 2
                                            // Image is positioned at offset.
                                            // Point (targetX, targetY) in image coordinates should be at (viewWidth/2, viewHeight/2).
                                            // Image TopLeft is at (offset.width - imageWidth/2 + viewWidth/2, ...) ???
                                            // Wait, SwiftUI Image frame center is at view center by default.
                                            // offset moves the center.
                                            
                                            // If offset is 0, center of image is at center of view.
                                            // We want (targetX, targetY) to be at center of view.
                                            // Current center is (imageWidth/2, imageHeight/2).
                                            // We need to shift by (imageWidth/2 - targetX, imageHeight/2 - targetY).
                                            
                                            let shiftX = (imageSize.width / 2) - targetX
                                            let shiftY = (imageSize.height / 2) - targetY
                                            
                                            // Clamp offset
                                            let maxOffsetX = max(0, (imageSize.width - viewSize.width) / 2)
                                            let maxOffsetY = max(0, (imageSize.height - viewSize.height) / 2)
                                            
                                            var newX = shiftX
                                            var newY = shiftY
                                            
                                            if newX > maxOffsetX { newX = maxOffsetX }
                                            if newX < -maxOffsetX { newX = -maxOffsetX }
                                            if newY > maxOffsetY { newY = maxOffsetY }
                                            if newY < -maxOffsetY { newY = -maxOffsetY }
                                            
                                            offset = CGSize(width: newX, height: newY)
                                            dragOffset = .zero
                                        }
                                    }
                                }
                        )
                        
                    if isOffline {
                        VStack {
                            Spacer()
                            Text("File Offline (Preview)")
                                .font(.caption)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                                .padding(.bottom, 20)
                        }
                    }
                } else {
                    if isOffline {
                        VStack {
                            Image(systemName: "externaldrive.badge.xmark")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("File Offline")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("Original file not found.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .task(id: url) {
                // 1. Check if RAW. If so, prioritize Embedded Preview for speed.
                let ext = url.pathExtension.lowercased()
                let isRaw = FileConstants.rawExtensions.contains(ext)
                
                if isRaw {
                    // Use ThumbnailGenerator (which uses QuickLook) to ensure correct rotation.
                    // Request a large size (screen size) for detail view.
                    if let screen = NSScreen.main {
                        let size = screen.frame.size
                        if let thumb = await ThumbnailGenerator.shared.generateThumbnail(for: url, size: size) {
                            self.image = thumb
                            self.isOffline = false
                            return
                        }
                    }
                }
                
                // 2. Try standard NSImage load (fastest for JPG/PNG)
                if let loaded = NSImage(contentsOf: url) {
                    self.image = loaded
                    self.isOffline = false
                    return
                }
                
                // 2. If failed, check if it's a RAW file or just failed standard load
                // Try RawImageLoader which attempts CI, BitmapRep, and CGImageSource
                if let rawImage = RawImageLoader.loadRaw(url: url) {
                    self.image = rawImage
                    self.isOffline = false
                    return
                }
                
                // 3. If still failed, try ThumbnailGenerator (as a last resort for preview)
                // Use a large size
                if let screen = NSScreen.main {
                    let size = screen.frame.size
                    if let thumb = await ThumbnailGenerator.shared.generateThumbnail(for: url, size: size) {
                        self.image = thumb
                        self.isOffline = false
                        return
                    }
                }
                
                // 4. Offline: Try to load cached thumbnail
                self.isOffline = true
                if let id = itemID {
                    // Try large preview first
                    if let preview = ThumbnailCacheService.shared.loadThumbnail(for: id, type: .preview) {
                        self.image = preview
                        print("DetailView: Loaded cached PREVIEW for offline file: \(url.lastPathComponent)")
                    } 
                    // Fallback to standard thumbnail
                    else if let cached = ThumbnailCacheService.shared.loadThumbnail(for: id, type: .thumbnail) {
                        self.image = cached
                        print("DetailView: Loaded cached thumbnail for offline file: \(url.lastPathComponent)")
                    } else {
                        print("DetailView: No cached thumbnail found for offline file: \(url.lastPathComponent) (ID: \(id))")
                    }
                } else {
                    print("DetailView: No itemID provided for offline file: \(url.lastPathComponent)")
                }
            }
            // Ensure Space key works even when focused on this view
            .background(
                Button("Quick Look") {
                    QuickLookService.shared.toggleQuickLook(for: [url])
                }
                .keyboardShortcut(.space, modifiers: [])
                .hidden()
            )
            // Ensure Space key works even when focused on this view
            .background(
                Button("Quick Look") {
                    QuickLookService.shared.toggleQuickLook(for: [url])
                }
                .keyboardShortcut(.space, modifiers: [])
                .hidden()
            )
        }
    }
}
    


