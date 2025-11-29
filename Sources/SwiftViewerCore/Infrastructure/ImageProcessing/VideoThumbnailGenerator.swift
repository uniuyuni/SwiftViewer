import Foundation
import AVFoundation
import AppKit

class VideoThumbnailGenerator {
    static let shared = VideoThumbnailGenerator()
    
    func generateThumbnail(for url: URL) async -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try await generator.image(at: .zero).image
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            print("Failed to generate thumbnail for \(url): \(error)")
            return nil
        }
    }
}
