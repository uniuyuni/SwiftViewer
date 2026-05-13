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
    
    // Zoom/Scroll State
    @State private var viewSize: CGSize = .zero
    @State private var isHovering: Bool = false
    @State private var hoverLocation: CGPoint = .zero
    @State private var scrollMonitor: Any?
    @State private var useNearestNeighbor: Bool = false
    
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
                        }
                    }
            )
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
            .onChange(of: url) { _, _ in
                // Reset zoom on image change
                currentScale = nil
                offset = .zero
                dragOffset = .zero
            }
            .onAppear { 
                viewSize = geometry.size 
                updateViewModelScale(newSize: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in 
                viewSize = newSize 
                updateViewModelScale(newSize: newSize)
            }
            .onChange(of: image) { _, _ in
                updateViewModelScale(newSize: viewSize)
            }
            .onChange(of: currentScale) { _, _ in
                updateViewModelScale(newSize: viewSize)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    self.hoverLocation = location
                    self.isHovering = true
                case .ended:
                    self.isHovering = false
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
}
    


