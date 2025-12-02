import XCTest
@testable import SwiftViewerCore

final class RAFDebugTests: XCTestCase {
    
    func testRAFExtraction() async throws {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let testfilesURL = currentDirectory.appendingPathComponent("Testfiles")
        
        let rafFiles = try fileManager.contentsOfDirectory(at: testfilesURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "raf" }
        
        print("\n=== RAF DEBUG ===")
        
        for file in rafFiles {
            print("Processing: \(file.lastPathComponent)")
            
            // 1. Check ThumbnailGenerator logic (Simulated)
            let ext = file.pathExtension.lowercased()
            let isRaw = ["raf", "cr3", "arw"].contains(ext) // Simplified
            let shouldSkipDownsample = isRaw && ext == "raf"
            print("  ThumbnailGenerator Skip Downsample: \(shouldSkipDownsample)")
            
            // 2. Check EmbeddedPreviewExtractor Orientation
            // We can't access private getOrientation, but we can check the result of extractPreview
            // Actually, extractPreview returns a rotated NSImage.
            // We can check the image size.
            // If it was rotated 90 degrees, width/height should be swapped relative to raw?
            // But we don't know raw dimensions easily without ExifTool.
            
            // Let's just check if we can run it without crashing.
            if let image = EmbeddedPreviewExtractor.shared.extractPreview(from: file) {
                print("  ✅ Extracted Image: \(image.size)")
            } else {
                print("  ❌ Extraction Failed")
            }
        }
        print("==================\n")
    }
}
