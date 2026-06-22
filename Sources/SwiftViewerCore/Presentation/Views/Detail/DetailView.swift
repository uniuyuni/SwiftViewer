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
                        ZoomableImageView(url: item.url, itemID: item.uuid, viewModel: viewModel)
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
    @ObservedObject var viewModel: MainViewModel
    
    @State private var image: NSImage?
    @State private var currentScale: CGFloat? = nil
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isOffline: Bool = false
    @State private var noPreview: Bool = false

    // Zoom/Scroll State
    @State private var viewSize: CGSize = .zero
    @State private var isHovering: Bool = false
    @State private var hoverLocation: CGPoint = .zero
    @State private var scrollMonitor: Any?
    @State private var useNearestNeighbor: Bool = false
    @State private var bitmapRep: NSBitmapImageRep? = nil
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let nsImage = image {
                    let imageSize = nsImage.size
                    let viewSize = geometry.size
                    let widthRatio = viewSize.width / imageSize.width
                    let heightRatio = viewSize.height / imageSize.height
                    let fitScale = min(widthRatio, heightRatio)
                    let actualScale = currentScale ?? fitScale

                    Image(nsImage: nsImage)
                        .interpolation(useNearestNeighbor ? .none : .high)
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
                                    let displayWidth = imageSize.width * actualScale
                                    let displayHeight = imageSize.height * actualScale
                                    let maxOffsetX = max(0, (displayWidth - viewSize.width) / 2)
                                    let maxOffsetY = max(0, (displayHeight - viewSize.height) / 2)
                                    
                                    var newX = offset.width + value.translation.width
                                    var newY = offset.height + value.translation.height
                                    
                                    if newX > maxOffsetX { newX = maxOffsetX }
                                    if newX < -maxOffsetX { newX = -maxOffsetX }
                                    if newY > maxOffsetY { newY = maxOffsetY }
                                    if newY < -maxOffsetY { newY = -maxOffsetY }
                                    
                                    withAnimation {
                                        offset = CGSize(width: newX, height: newY)
                                        dragOffset = .zero
                                    }
                                    
                                    persistZoomState(nsImage: nsImage, viewSize: viewSize)
                                }
                            : nil
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
            // Move SpatialTapGesture from Image to ZStack so `event.location` is perfectly relative to `viewSize`.
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { event in
                        guard let nsImage = self.image else { return }
                        let location = event.location
                        
                        let widthRatio = geometry.size.width / nsImage.size.width
                        let heightRatio = geometry.size.height / nsImage.size.height
                        let fitScale = min(widthRatio, heightRatio)
                        let actualScale = self.currentScale ?? fitScale
                        
                        let isFit = abs(actualScale - fitScale) < 0.01
                        
                        if isFit {
                            // Zoom to 100%
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
                            
                            var newOffsetX = -newDistance.width
                            var newOffsetY = -newDistance.height
                            
                            let newDisplayWidth = nsImage.size.width * newScale
                            let newDisplayHeight = nsImage.size.height * newScale
                            let maxOffsetX = max(0, (newDisplayWidth - geometry.size.width) / 2)
                            let maxOffsetY = max(0, (newDisplayHeight - geometry.size.height) / 2)
                            
                            if newOffsetX > maxOffsetX { newOffsetX = maxOffsetX }
                            if newOffsetX < -maxOffsetX { newOffsetX = -maxOffsetX }
                            if newOffsetY > maxOffsetY { newOffsetY = maxOffsetY }
                            if newOffsetY < -maxOffsetY { newOffsetY = -maxOffsetY }
                            
                            withAnimation {
                                self.currentScale = newScale
                                self.offset = CGSize(width: newOffsetX, height: newOffsetY)
                                self.dragOffset = .zero
                            }
                            persistZoomState(nsImage: nsImage, viewSize: geometry.size)
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                if let cs = self.currentScale, cs > 1.0 {
                                    self.useNearestNeighbor = true
                                }
                            }
                        } else {
                            // Zoom to Fit
                            self.useNearestNeighbor = false
                            
                            DispatchQueue.main.async {
                                withAnimation {
                                    self.currentScale = nil
                                    self.offset = .zero
                                    self.dragOffset = .zero
                                }
                            }
                            persistZoomState(nsImage: nsImage, viewSize: geometry.size)
                        }
                    }
            )
            .clipped()
            .task(id: url) {
                // Reset the no-preview flag for the newly selected file.
                // (Do NOT clear `image` here to avoid flicker on normal navigation.)
                self.noPreview = false

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
                
                // 4. All decode/extract attempts failed. Distinguish two cases:
                if FileManager.default.fileExists(atPath: url.path) {
                    // File is present but no preview could be produced (corrupt/unsupported,
                    // no embedded preview, etc.). Show a "no preview" message, not the previous image.
                    self.image = nil
                    self.isOffline = false
                    self.noPreview = true
                    return
                }

                // Genuinely offline (original missing): try cached thumbnail.
                self.isOffline = true
                self.noPreview = false
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
                        // No cache: clear so the previous image does not linger behind the offline message.
                        self.image = nil
                        print("DetailView: No cached thumbnail found for offline file: \(url.lastPathComponent) (ID: \(id))")
                    }
                } else {
                    self.image = nil
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
            .onChange(of: url) { _, _ in
                // 画像読み込み完了後（onChange of image）に拡大状態を復元する。
                // 切り替え直後にドラッグ中の差分だけ残るのは不自然なのでここでクリアする。
                dragOffset = .zero
            }
            .onAppear {
                viewSize = geometry.size
                if let img = image {
                    restoreZoomStateIfNeeded(nsImage: img, viewSize: geometry.size)
                    if bitmapRep == nil { rebuildBitmapRep(from: img) }
                }
                updateViewModelScale(newSize: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in 
                viewSize = newSize 
                if let img = image {
                    // ウィンドウサイズ変更時も、画像外を表示しないように位置をクランプ
                    offset = clampOffset(
                        offset,
                        imageSize: img.size,
                        viewSize: newSize,
                        scale: (currentScale ?? min(newSize.width / img.size.width, newSize.height / img.size.height))
                    )
                    persistZoomState(nsImage: img, viewSize: newSize)
                }
                updateViewModelScale(newSize: newSize)
            }
            .onChange(of: image) { _, _ in
                if let img = image {
                    restoreZoomStateIfNeeded(nsImage: img, viewSize: viewSize)
                    rebuildBitmapRep(from: img)
                } else {
                    bitmapRep = nil
                }
                updateViewModelScale(newSize: viewSize)
            }
            .onChange(of: currentScale) { _, _ in
                if let img = image {
                    // スケール変更時も画像外を表示しないようクランプ
                    offset = clampOffset(
                        offset,
                        imageSize: img.size,
                        viewSize: viewSize,
                        scale: (currentScale ?? min(viewSize.width / img.size.width, viewSize.height / img.size.height))
                    )
                    persistZoomState(nsImage: img, viewSize: viewSize)
                }
                updateViewModelScale(newSize: viewSize)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    self.hoverLocation = location
                    self.isHovering = true
                    updateCursorDebugInfo(location: location, viewSize: geometry.size)
                case .ended:
                    self.isHovering = false
                    viewModel.cursorImagePoint = nil
                    viewModel.cursorRGB = nil
                }
            }
            .onAppear {
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard self.isHovering else { return event }
                    
                    let deltaY = event.deltaY
                    // Increase sensitivity by multiplying delta or using larger step
                    let zoomStep = deltaY * 0.05
                    let zoomMultiplier = exp(zoomStep)
                    if abs(zoomStep) < 0.001 { return event }
                    
                    guard let nsImage = self.image else { return event }
                    let imgSize = nsImage.size
                    
                    let widthRatio = viewSize.width / imgSize.width
                    let heightRatio = viewSize.height / imgSize.height
                    let fitScale = min(widthRatio, heightRatio)
                    let actualScale = self.currentScale ?? fitScale
                    
                    var newScale = actualScale * zoomMultiplier
                    newScale = max(0.01, min(newScale, 50.0)) // 1% to 5000%
                    
                    let scaleVal = newScale / actualScale
                    let viewCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                    let pointerOffsetFromCenter = CGSize(
                        width: self.hoverLocation.x - viewCenter.x,
                        height: self.hoverLocation.y - viewCenter.y
                    )
                    
                    var newOffsetX = self.offset.width * scaleVal - pointerOffsetFromCenter.width * (scaleVal - 1)
                    var newOffsetY = self.offset.height * scaleVal - pointerOffsetFromCenter.height * (scaleVal - 1)
                    
                    let displayWidth = imgSize.width * newScale
                    let displayHeight = imgSize.height * newScale
                    let maxOffsetX = max(0, (displayWidth - viewSize.width) / 2)
                    let maxOffsetY = max(0, (displayHeight - viewSize.height) / 2)
                    
                    if newOffsetX > maxOffsetX { newOffsetX = maxOffsetX }
                    if newOffsetX < -maxOffsetX { newOffsetX = -maxOffsetX }
                    if newOffsetY > maxOffsetY { newOffsetY = maxOffsetY }
                    if newOffsetY < -maxOffsetY { newOffsetY = -maxOffsetY }
                    
                    self.currentScale = newScale
                    self.offset = CGSize(width: newOffsetX, height: newOffsetY)
                    self.useNearestNeighbor = newScale > 1.0
                    if let img = self.image {
                        self.persistZoomState(nsImage: img, viewSize: self.viewSize)
                    }
                    
                    return nil // Consume event
                }
            }
            .onDisappear {
                if let monitor = scrollMonitor {
                    NSEvent.removeMonitor(monitor)
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
        // Normalize to 0..1
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
        
        // Fitの場合は状態を持たない（=常に中央/オフセット無し）
        guard let persistedScale = viewModel.persistedZoomScale else {
            currentScale = nil
            offset = .zero
            dragOffset = .zero
            useNearestNeighbor = false
            return
        }
        
        let center = viewModel.persistedZoomCenterNormalized ?? CGPoint(x: 0.5, y: 0.5)
        currentScale = persistedScale
        offset = offsetForCenterNormalized(center, imageSize: imgSize, viewSize: viewSize, scale: persistedScale)
        dragOffset = .zero
        useNearestNeighbor = persistedScale > 1.0
    }
    
    private func persistZoomState(nsImage: NSImage, viewSize: CGSize) {
        let imgSize = nsImage.size
        guard imgSize.width > 0, imgSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return }
        
        // Fit表示なら状態を破棄
        guard let scale = currentScale else {
            viewModel.persistedZoomScale = nil
            viewModel.persistedZoomCenterNormalized = nil
            return
        }
        
        viewModel.persistedZoomScale = scale
        viewModel.persistedZoomCenterNormalized = currentCenterNormalized(imageSize: imgSize, scale: scale, offset: offset)
    }
    
    private func updateViewModelScale(newSize: CGSize) {
        guard let nsImage = image else { return }
        let widthRatio = newSize.width / nsImage.size.width
        let heightRatio = newSize.height / nsImage.size.height
        let fitScale = min(widthRatio, heightRatio)
        let actual = currentScale ?? fitScale
        DispatchQueue.main.async {
            viewModel.imageZoomScale = actual
        }
    }

    private func rebuildBitmapRep(from nsImage: NSImage) {
        if let existing = nsImage.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            bitmapRep = existing
            return
        }
        if let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            bitmapRep = NSBitmapImageRep(cgImage: cg)
        } else {
            bitmapRep = nil
        }
    }

    private func updateCursorDebugInfo(location: CGPoint, viewSize: CGSize) {
        guard let nsImage = image else {
            viewModel.cursorImagePoint = nil
            viewModel.cursorRGB = nil
            return
        }
        let imgSize = nsImage.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }

        let widthRatio = viewSize.width / imgSize.width
        let heightRatio = viewSize.height / imgSize.height
        let fitScale = min(widthRatio, heightRatio)
        let actualScale = currentScale ?? fitScale

        let displayWidth = imgSize.width * actualScale
        let displayHeight = imgSize.height * actualScale
        let displayLeft = (viewSize.width - displayWidth) / 2 + offset.width + dragOffset.width
        let displayTop = (viewSize.height - displayHeight) / 2 + offset.height + dragOffset.height

        let imgX = (location.x - displayLeft) / actualScale
        let imgY = (location.y - displayTop) / actualScale

        if imgX < 0 || imgY < 0 || imgX >= imgSize.width || imgY >= imgSize.height {
            viewModel.cursorImagePoint = nil
            viewModel.cursorRGB = nil
            return
        }

        viewModel.cursorImagePoint = CGPoint(x: floor(imgX), y: floor(imgY))

        guard let bitmap = bitmapRep else {
            viewModel.cursorRGB = nil
            return
        }
        let pxX = Int(imgX * CGFloat(bitmap.pixelsWide) / imgSize.width)
        let pxY = Int(imgY * CGFloat(bitmap.pixelsHigh) / imgSize.height)
        let cx = max(0, min(bitmap.pixelsWide - 1, pxX))
        let cy = max(0, min(bitmap.pixelsHigh - 1, pxY))
        if let color = bitmap.colorAt(x: cx, y: cy)?.usingColorSpace(.sRGB) {
            let r = UInt8(max(0, min(255, color.redComponent * 255)))
            let g = UInt8(max(0, min(255, color.greenComponent * 255)))
            let b = UInt8(max(0, min(255, color.blueComponent * 255)))
            viewModel.cursorRGB = PixelRGB(r: r, g: g, b: b)
        } else {
            viewModel.cursorRGB = nil
        }
    }
}
    

