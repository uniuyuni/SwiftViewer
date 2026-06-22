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
                    SubZoomableImageView(url: item.url, itemID: item.uuid, viewModel: viewModel)
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
    @ObservedObject var viewModel: MainViewModel
    
    @State private var image: NSImage?
    @State private var currentScale: CGFloat? = nil // nil = fit
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isOffline: Bool = false
    @State private var noPreview: Bool = false
    @State private var viewSize: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let nsImage = image {
                    let imageSize = nsImage.size
                    let widthRatio = geometry.size.width / imageSize.width
                    let heightRatio = geometry.size.height / imageSize.height
                    let fitScale = min(widthRatio, heightRatio)
                    let actualScale = currentScale ?? fitScale
                    
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: imageSize.width * actualScale,
                            height: imageSize.height * actualScale
                        )
                        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
                        .gesture(
                            currentScale != nil ?
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    var newOffset = CGSize(
                                        width: offset.width + value.translation.width,
                                        height: offset.height + value.translation.height
                                    )
                                    newOffset = clampOffset(
                                        newOffset,
                                        imageSize: imageSize,
                                        viewSize: geometry.size,
                                        scale: actualScale
                                    )
                                    
                                    withAnimation {
                                        offset = newOffset
                                        dragOffset = .zero
                                    }
                                    
                                    persistZoomState(nsImage: nsImage, viewSize: geometry.size)
                                }
                            : nil
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { event in
                                    let location = event.location
                                    
                                    let isFit = abs(actualScale - fitScale) < 0.01
                                    
                                    if isFit {
                                        // Zoom to 100%（クリック位置を中心へ）
                                        let newScale: CGFloat = 1.0
                                        let scaleVal = newScale / actualScale
                                        
                                        let viewCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                        let pointerOffsetFromCenter = CGSize(
                                            width: location.x - viewCenter.x,
                                            height: location.y - viewCenter.y
                                        )
                                        
                                        let distanceToImageCenter = CGSize(
                                            width: pointerOffsetFromCenter.width - self.offset.width,
                                            height: pointerOffsetFromCenter.height - self.offset.height
                                        )
                                        
                                        let newDistance = CGSize(
                                            width: distanceToImageCenter.width * scaleVal,
                                            height: distanceToImageCenter.height * scaleVal
                                        )
                                        
                                        var newOffset = CGSize(width: -newDistance.width, height: -newDistance.height)
                                        newOffset = clampOffset(
                                            newOffset,
                                            imageSize: imageSize,
                                            viewSize: geometry.size,
                                            scale: newScale
                                        )
                                        
                                        withAnimation {
                                            self.currentScale = newScale
                                            self.offset = newOffset
                                            self.dragOffset = .zero
                                        }
                                        persistZoomState(nsImage: nsImage, viewSize: geometry.size)
                                    } else {
                                        // Zoom to Fit
                                        withAnimation {
                                            self.currentScale = nil
                                            self.offset = .zero
                                            self.dragOffset = .zero
                                        }
                                        persistZoomState(nsImage: nsImage, viewSize: geometry.size)
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
                    if noPreview {
                        VStack {
                            Image(systemName: "eye.slash")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No Preview Available")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("This file has no preview image.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isOffline {
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
            .onAppear {
                viewSize = geometry.size
                if let img = image {
                    restoreZoomStateIfNeeded(nsImage: img, viewSize: geometry.size)
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                viewSize = newSize
                if let img = image {
                    let imgSize = img.size
                    let fitScale = min(newSize.width / imgSize.width, newSize.height / imgSize.height)
                    offset = clampOffset(offset, imageSize: imgSize, viewSize: newSize, scale: (currentScale ?? fitScale))
                    persistZoomState(nsImage: img, viewSize: newSize)
                }
            }
            .onChange(of: image) { _, _ in
                if let img = image {
                    restoreZoomStateIfNeeded(nsImage: img, viewSize: viewSize)
                }
            }
            .task(id: url) {
                // Reset the no-preview flag for the newly selected file.
                // (Do NOT clear `image` here to avoid flicker on normal navigation.)
                self.noPreview = false

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
                
                // 4. All decode/extract attempts failed. Distinguish two cases:
                if FileManager.default.fileExists(atPath: url.path) {
                    // File is present but no preview could be produced.
                    self.image = nil
                    self.isOffline = false
                    self.noPreview = true
                    return
                }

                // Genuinely offline (original missing): try cached thumbnail.
                self.isOffline = true
                self.noPreview = false
                if let id = itemID {
                    if let preview = ThumbnailCacheService.shared.loadThumbnail(for: id, type: .preview) {
                        self.image = preview
                    } else if let cached = ThumbnailCacheService.shared.loadThumbnail(for: id, type: .thumbnail) {
                        self.image = cached
                    } else {
                        // No cache: clear so the previous image does not linger.
                        self.image = nil
                    }
                } else {
                    self.image = nil
                }
            }
        }
    }
    
    private func clampOffset(_ proposed: CGSize, imageSize: CGSize, viewSize: CGSize, scale: CGFloat) -> CGSize {
        let displayWidth = imageSize.width * scale
        let displayHeight = imageSize.height * scale
        let maxOffsetX = max(0, (displayWidth - viewSize.width) / 2)
        let maxOffsetY = max(0, (displayHeight - viewSize.height) / 2)
        
        var x = proposed.width
        var y = proposed.height
        
        if x > maxOffsetX { x = maxOffsetX }
        if x < -maxOffsetX { x = -maxOffsetX }
        if y > maxOffsetY { y = maxOffsetY }
        if y < -maxOffsetY { y = -maxOffsetY }
        
        return CGSize(width: x, height: y)
    }
    
    private func currentCenterNormalized(imageSize: CGSize, scale: CGFloat, offset: CGSize) -> CGPoint {
        let imgCenter = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let center = CGPoint(
            x: imgCenter.x - (offset.width / scale),
            y: imgCenter.y - (offset.height / scale)
        )
        let nx = imageSize.width > 0 ? center.x / imageSize.width : 0.5
        let ny = imageSize.height > 0 ? center.y / imageSize.height : 0.5
        return CGPoint(x: min(1.0, max(0.0, nx)), y: min(1.0, max(0.0, ny)))
    }
    
    private func offsetForCenterNormalized(_ center: CGPoint, imageSize: CGSize, viewSize: CGSize, scale: CGFloat) -> CGSize {
        let imgCenter = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let desiredPoint = CGPoint(x: center.x * imageSize.width, y: center.y * imageSize.height)
        let rawOffset = CGSize(
            width: (imgCenter.x - desiredPoint.x) * scale,
            height: (imgCenter.y - desiredPoint.y) * scale
        )
        return clampOffset(rawOffset, imageSize: imageSize, viewSize: viewSize, scale: scale)
    }
    
    private func restoreZoomStateIfNeeded(nsImage: NSImage, viewSize: CGSize) {
        let imgSize = nsImage.size
        guard imgSize.width > 0, imgSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return }
        
        guard let persistedScale = viewModel.persistedZoomScale else {
            currentScale = nil
            offset = .zero
            dragOffset = .zero
            return
        }
        
        let center = viewModel.persistedZoomCenterNormalized ?? CGPoint(x: 0.5, y: 0.5)
        currentScale = persistedScale
        offset = offsetForCenterNormalized(center, imageSize: imgSize, viewSize: viewSize, scale: persistedScale)
        dragOffset = .zero
    }
    
    private func persistZoomState(nsImage: NSImage, viewSize: CGSize) {
        let imgSize = nsImage.size
        guard imgSize.width > 0, imgSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return }
        
        guard let scale = currentScale else {
            viewModel.persistedZoomScale = nil
            viewModel.persistedZoomCenterNormalized = nil
            return
        }
        
        viewModel.persistedZoomScale = scale
        viewModel.persistedZoomCenterNormalized = currentCenterNormalized(imageSize: imgSize, scale: scale, offset: offset)
    }
}
