import SwiftUI
import CoreData

struct SubPreviewView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all) // Use black for immersive preview
            
            if let item = viewModel.currentFile {
                if FileConstants.allowedVideoExtensions.contains(item.url.pathExtension.lowercased()) {
                    VideoPlayerView(url: item.url)
                } else {
                    SubZoomableImageView(url: item.url, itemID: item.uuid)
                }
            } else {
                ContentUnavailableView {
                    Label("No Selection", systemImage: "photo.badge.plus")
                } description: {
                    Text("Select an item to view.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Copied from DetailView.swift to ensure consistent rendering without refactoring dependencies
private struct SubZoomableImageView: View {
    let url: URL
    let itemID: UUID?
    
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
                    if let screen = NSScreen.main {
                        let size = screen.frame.size
                        if let thumb = await ThumbnailGenerator.shared.generateThumbnail(for: url, size: size) {
                            self.image = thumb
                            self.isOffline = false
                            return
                        }
                    }
                }
                
                // 2. Try standard NSImage load
                if let loaded = NSImage(contentsOf: url) {
                    self.image = loaded
                    self.isOffline = false
                    return
                }
                
                // 3. Raw Loader fallback
                if let rawImage = RawImageLoader.loadRaw(url: url) {
                    self.image = rawImage
                    self.isOffline = false
                    return
                }
                
                // 4. Offline/Cache
                self.isOffline = true
                if let id = itemID {
                    if let preview = ThumbnailCacheService.shared.loadThumbnail(for: id, type: .preview) {
                        self.image = preview
                    } else if let cached = ThumbnailCacheService.shared.loadThumbnail(for: id, type: .thumbnail) {
                        self.image = cached
                    }
                }
            }
        }
    }
}
