import XCTest
import ImageIO
@testable import SwiftViewerCore

final class RAFDebugDeepDive: XCTestCase {
    
    func testRAFDeepDive() async throws {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let testfilesURL = currentDirectory.appendingPathComponent("Testfiles")
        
        // Find a RAF file
        let rafFile = try fileManager.contentsOfDirectory(at: testfilesURL, includingPropertiesForKeys: nil)
            .first { $0.pathExtension.lowercased() == "raf" }
        
        guard let file = rafFile else {
            print("❌ No RAF file found in Testfiles")
            return
        }
        
        print("\n=== RAF DEEP DIVE ===")
        print("File: \(file.lastPathComponent)")
        
        // 1. Simulate EmbeddedPreviewExtractor Logic
        print("\n--- EmbeddedPreviewExtractor Logic ---")
        if let rawSource = CGImageSourceCreateWithURL(file as CFURL, nil),
           let rawProps = CGImageSourceCopyPropertiesAtIndex(rawSource, 0, nil) as? [String: Any] {
            
            let rawW = rawProps[kCGImagePropertyPixelWidth as String] as? Int ?? -1
            let rawH = rawProps[kCGImagePropertyPixelHeight as String] as? Int ?? -1
            let rawOrient = rawProps[kCGImagePropertyOrientation as String] as? Int ?? -1
            
            print("RAW Properties (CGImageSource):")
            print("  Width: \(rawW)")
            print("  Height: \(rawH)")
            print("  Orientation: \(rawOrient)")
            
            let isRawPortrait = rawH > rawW
            print("  isRawPortrait (H > W): \(isRawPortrait)")
            
            // Extract Embedded Data
            // We need to simulate extracting data. EmbeddedPreviewExtractor uses JpgFromRaw or PreviewImage.
            // For this test, we'll try to get the embedded thumbnail from the RAW source directly if possible,
            // or just assume we have data.
            // Actually, let's use EmbeddedPreviewExtractor to get the data if we can, but it's private.
            // We will just assume we have the data and check properties if we can get them.
            // Let's try to get the first image from source (which might be the thumbnail/preview in some formats, or the raw).
            // For RAF, index 0 is usually the RAW.
            // Does RAF have other images?
            let count = CGImageSourceGetCount(rawSource)
            print("  Image Count: \(count)")
            
            // Try to find the embedded preview via ExifTool (since that's what Extractor does)
            // We can't easily call private methods.
            // But we can check what `EmbeddedPreviewExtractor.extractPreview` does.
            // It calls `getOrientation`.
            // We want to see if `getOrientation` logic holds.
            
            // Let's just check the RAW dimensions.
            // If rawW > rawH (Landscape), then `isRawPortrait` is FALSE.
            // And if the image is visually Portrait (Orient 8), then we MUST check Orientation.
        }
        
        // 2. Check ExifReader Logic
        print("\n--- ExifReader Logic ---")
        if let meta = ExifReader.shared.readExifUsingExifTool(from: file) {
            print("ExifReader Result:")
            print("  Orientation: \(meta.orientation ?? -1)")
            print("  Width: \(meta.width ?? -1)")
            print("  Height: \(meta.height ?? -1)")
            
            if let w = meta.width, let h = meta.height {
                if w > h { print("  Result: Landscape (Width > Height)") }
                else { print("  Result: Portrait (Height > Width)") }
            }
        } else {
            print("❌ ExifReader Failed")
        }
        
        print("==================\n")
    }
}
