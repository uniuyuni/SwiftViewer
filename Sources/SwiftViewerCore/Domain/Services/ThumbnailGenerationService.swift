import Foundation
import Combine
import CoreData
import AppKit

public class ThumbnailGenerationService: ObservableObject {
    public static let shared = ThumbnailGenerationService()
    
    @Published public var isGenerating = false
    @Published public var progress: Double = 0.0
    @Published public var remainingCount: Int = 0
    @Published public var statusMessage: String = ""
    
    private var queue: [NSManagedObjectID] = []
    private var isProcessing = false
    private var currentTask: Task<Void, Never>?
    private var lastUpdateTime: Date?
    
    private init() {}
    
    private var totalCount: Int = 0
    
    public func enqueue(items: [NSManagedObjectID]) {
        if queue.isEmpty {
            totalCount = items.count
            progress = 0.0
        } else {
            totalCount += items.count
        }
        queue.append(contentsOf: items)
        remainingCount = queue.count
        
        // Ensure UI updates immediately on MainActor
        Task { @MainActor in
            // Check if still valid (not cancelled)
            guard self.remainingCount > 0 else { return }
            
            if !self.isGenerating {
                self.isGenerating = true
                self.statusMessage = "Generating thumbnails..."
            }
            // Update progress immediately
            if self.totalCount > 0 {
                self.progress = Double(self.totalCount - self.remainingCount) / Double(self.totalCount)
            }
        }
        
        processQueue()
    }
    
    public func cancelAll() {
        currentTask?.cancel()
        queue.removeAll()
        remainingCount = 0
        totalCount = 0
        progress = 0.0
        isGenerating = false
        isProcessing = false
        statusMessage = "Cancelled"
    }
    
    private var isSuspended = false
    
    public func suspend() {
        isSuspended = true
    }
    
    public func resume() {
        isSuspended = false
        processQueue()
    }
    
    private func processQueue() {
        guard !isProcessing, !queue.isEmpty else {
            if queue.isEmpty {
                // Don't overwrite "Cancelled" state
                if statusMessage != "Cancelled" {
                    isGenerating = false
                    statusMessage = "Finished"
                    progress = 1.0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if !self.isGenerating {
                            self.statusMessage = ""
                            self.progress = 0.0
                        }
                    }
                }
            }
            return
        }
        
        // Don't start if suspended
        if isSuspended {
            return
        }
        
        isProcessing = true
        isGenerating = true
        statusMessage = "Generating thumbnails..."
        
        currentTask = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            let context = PersistenceController.shared.newBackgroundContext()
            
            while !self.queue.isEmpty {
                if Task.isCancelled { break }
                
                // Check suspension
                if self.isSuspended {
                    await MainActor.run {
                        self.isProcessing = false
                    }
                    return
                }
                
                // Process in batches
                let batchSize = 10
                let batch = Array(self.queue.prefix(batchSize))
                
                await context.perform {
                    for objectID in batch {
                        if let item = try? context.existingObject(with: objectID) as? MediaItem,
                           let path = item.originalPath {
                            let url = URL(fileURLWithPath: path)
                            let uuid = item.id ?? UUID()
                            
                            // Generate Thumbnail and Metadata
                            let size = CGSize(width: 600, height: 600)
                            let (thumb, metadata) = ThumbnailGenerator.shared.generateThumbnailAndMetadataSync(for: url, size: size)
                            
                            if let thumb = thumb {
                                ThumbnailCacheService.shared.saveThumbnail(image: thumb, for: uuid, type: .thumbnail)
                            }
                            
                            // Generate Preview (Large)
                            // For RAWs, this might be slow if we decode full image.
                            // But ThumbnailGenerator handles RAWs efficiently via downsampling or embedded preview.
                            // We use a larger size, e.g., 1024x1024 (User requested max long edge 1024)
                            // Use user setting for preview size
                            let previewSizeSetting = UserDefaults.standard.integer(forKey: "previewImageSize")
                            let targetSize = previewSizeSetting > 0 ? CGFloat(previewSizeSetting) : 1024.0
                            let previewSize = CGSize(width: targetSize, height: targetSize)
                            
                            if let preview = ThumbnailGenerator.shared.generateThumbnailSync(for: url, size: previewSize) {
                                ThumbnailCacheService.shared.saveThumbnail(image: preview, for: uuid, type: .preview)
                            }
                            
                            if let meta = metadata {
                                // Update MediaItem for sorting
                                item.captureDate = meta.dateTimeOriginal
                                item.width = Int32(meta.width ?? 0)
                                item.height = Int32(meta.height ?? 0)
                                item.orientation = Int16(meta.orientation ?? 1)
                                
                                // Create/Update ExifData entity if needed (simplified)
                                if item.exifData == nil {
                                    let exif = ExifData(context: context)
                                    exif.id = UUID()
                                    item.exifData = exif
                                }
                                
                                if let exif = item.exifData {
                                    exif.dateTimeOriginal = meta.dateTimeOriginal
                                    exif.cameraMake = meta.cameraMake
                                    exif.cameraModel = meta.cameraModel
                                    exif.lensModel = meta.lensModel
                                    exif.focalLength = meta.focalLength ?? 0
                                    exif.aperture = meta.aperture ?? 0
                                    exif.shutterSpeed = meta.shutterSpeed
                                    exif.iso = Int32(meta.iso ?? 0)
                                }
                            }
                        }
                    }
                    // Save changes to DB
                    try? context.save()
                }
                
                // Yield to prevent blocking
                await Task.yield()
                
                await MainActor.run {
                    self.queue.removeFirst(min(batch.count, self.queue.count))
                    self.remainingCount = self.queue.count
                    
                    // Throttle UI updates (e.g., every 0.5 seconds)
                    let now = Date()
                    if self.lastUpdateTime == nil || now.timeIntervalSince(self.lastUpdateTime!) > 0.5 || self.remainingCount == 0 {
                        if self.totalCount > 0 {
                            self.progress = Double(self.totalCount - self.remainingCount) / Double(self.totalCount)
                        }
                        self.lastUpdateTime = now
                    }
                }
            }
            
            await MainActor.run {
                self.isProcessing = false
                self.processQueue() // Check if more added or finished
            }
        }
    }
}
