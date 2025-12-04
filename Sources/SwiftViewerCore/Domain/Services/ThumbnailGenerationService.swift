import AppKit
import Combine
import CoreData
import Foundation

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
                self.progress =
                    Double(self.totalCount - self.remainingCount) / Double(self.totalCount)
            }
        }

        processQueue()
    }

    public func cancelAll() {
        currentTask?.cancel()
        queue.removeAll()
        cancelledItems.removeAll()
        remainingCount = 0
        totalCount = 0
        progress = 0.0
        isGenerating = false
        isProcessing = false
        statusMessage = "Cancelled"
    }

    private var cancelledItems: Set<NSManagedObjectID> = []

    public func cancelGeneration(for items: [NSManagedObjectID]) {
        // Remove from queue
        let itemSet = Set(items)
        queue.removeAll { itemSet.contains($0) }

        // Add to cancelled set so currently processing items can skip
        cancelledItems.formUnion(itemSet)

        // Update counts
        remainingCount = queue.count
        if totalCount > 0 {
            progress = Double(totalCount - remainingCount) / Double(totalCount)
        }

        if queue.isEmpty && !isProcessing {
            isGenerating = false
            statusMessage = "Cancelled"
            progress = 0.0
        }
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
                let batchSize = 10  // Restore batch size to 10 for better throughput
                let batch = Array(self.queue.prefix(batchSize))

                // 1. Fetch Data (Sync on Context)
                struct ItemData {
                    let objectID: NSManagedObjectID
                    let url: URL
                    let uuid: UUID
                }

                let itemsToProcess: [ItemData] = await context.perform {
                    var result: [ItemData] = []
                    for objectID in batch {
                        // Check if cancelled
                        if self.cancelledItems.contains(objectID) {
                            continue
                        }
                        
                        if let item = try? context.existingObject(with: objectID) as? MediaItem,
                           let path = item.originalPath {
                            let url = URL(fileURLWithPath: path)
                            let uuid = item.id ?? UUID()
                            result.append(ItemData(objectID: objectID, url: url, uuid: uuid))
                        }
                    }
                    return result
                }
                
                // Clean up cancelled items set periodically
                if self.cancelledItems.count > 1000 {
                    await MainActor.run {
                        self.cancelledItems.removeAll()
                    }
                }

                // 2. Generate Thumbnails (Async, Concurrent, No Context Lock)
                for itemData in itemsToProcess {
                    if Task.isCancelled { break }
                    
                    // Check specific item cancellation
                    if self.cancelledItems.contains(itemData.objectID) {
                        continue
                    }

                    let url = itemData.url
                    let uuid = itemData.uuid

                    // Generate Thumbnail and Metadata
                    let size = CGSize(width: 600, height: 600)
                    let (thumb, metadata) = await ThumbnailGenerator.shared
                        .generateThumbnailAndMetadataAsync(for: url, size: size)

                    // Check cancellation AGAIN before saving
                    if self.cancelledItems.contains(itemData.objectID) {
                        continue
                    }

                    if let thumb = thumb {
                        ThumbnailCacheService.shared.saveThumbnail(
                            image: thumb, for: uuid, type: .thumbnail)
                    }

                    // Generate Preview (Large)
                    let previewSizeSetting = UserDefaults.standard.integer(
                        forKey: "previewImageSize")
                    let targetSize = previewSizeSetting > 0 ? CGFloat(previewSizeSetting) : 1024.0
                    let previewSize = CGSize(width: targetSize, height: targetSize)
                    
                    // Check cancellation before preview generation (optimization)
                    if self.cancelledItems.contains(itemData.objectID) {
                        continue
                    }

                    if let preview = await ThumbnailGenerator.shared.generateThumbnailAsync(
                        for: url, size: previewSize)
                    {
                        // Check cancellation AGAIN before saving preview
                        if self.cancelledItems.contains(itemData.objectID) {
                            continue
                        }
                        
                        ThumbnailCacheService.shared.saveThumbnail(
                            image: preview, for: uuid, type: .preview)
                    }

                    // 3. Save Metadata (Sync on Context)
                    if let meta = metadata {
                        // Check cancellation before context perform
                        if self.cancelledItems.contains(itemData.objectID) {
                            continue
                        }
                        
                        await context.perform {
                            // Final check inside context
                            if self.cancelledItems.contains(itemData.objectID) {
                                return
                            }
                            
                            if let item = try? context.existingObject(with: itemData.objectID)
                                as? MediaItem
                            {
                                // Update MediaItem for sorting
                                item.captureDate = meta.dateTimeOriginal
                                item.width = Int32(meta.width ?? 0)
                                item.height = Int32(meta.height ?? 0)
                                item.orientation = Int16(meta.orientation ?? 1)

                                // Create/Update ExifData entity if needed
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
                                try? context.save()
                            }
                        }
                    }
                }

                // Yield to prevent blocking
                await Task.yield()

                await MainActor.run {
                    self.queue.removeFirst(min(batch.count, self.queue.count))
                    self.remainingCount = self.queue.count

                    // Throttle UI updates (e.g., every 0.5 seconds)
                    let now = Date()
                    if self.lastUpdateTime == nil
                        || now.timeIntervalSince(self.lastUpdateTime!) > 0.5
                        || self.remainingCount == 0
                    {
                        if self.totalCount > 0 {
                            self.progress =
                                Double(self.totalCount - self.remainingCount)
                                / Double(self.totalCount)
                        }
                        self.lastUpdateTime = now
                    }
                }
            }

            await MainActor.run {
                self.isProcessing = false
                self.processQueue()  // Check if more added or finished
            }
        }
    }
}
