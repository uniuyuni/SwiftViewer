import XCTest
@testable import SwiftViewerCore
import ImageIO

final class RotationDebugTests: XCTestCase {
    
    func testDumpRotationMetadata() async throws {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let testfilesURL = currentDirectory.appendingPathComponent("Testfiles")
        
        guard fileManager.fileExists(atPath: testfilesURL.path) else {
            print("Testfiles not found.")
            return
        }
        
        let files = try fileManager.contentsOfDirectory(at: testfilesURL, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        print("\n=== RAW ROTATION DEBUG REPORT ===")
        print(String(format: "%-20s | %-10s | %-10s | %-15s", "Filename", "CG Orient", "Exif Orient", "Preview Size"))
        print(String(repeating: "-", count: 65))
        
        for file in files {
            print("Processing: \(file.lastPathComponent)")
            // 1. CGImageSource Orientation
            var cgOrient = "N/A"
            if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
               let orient = props[kCGImagePropertyOrientation as String] as? Int {
                cgOrient = "\(orient)"
            }
            
            // 2. ExifTool Orientation
            var exifOrient = "N/A"
            /*
            if let meta = ExifReader.shared.readExifUsingExifTool(from: file),
               let orient = meta.orientation {
                exifOrient = "\(orient)"
            }
            */
            exifOrient = "Skipped"
            
            // 3. Embedded Preview Size (Raw, no rotation applied yet)
            var previewSize = "N/A"
            // We want to check the size of the extracted preview BEFORE we rotate it in our code.
            // But EmbeddedPreviewExtractor.extractPreview applies rotation automatically.
            // So we'll use a raw extraction helper here or just check what extractPreview returns (which is rotated).
            // Let's check the ROTATED size to see if it matches expectations (Portrait vs Landscape).
            
            /*
            if let image = await Task.detached(operation: {
                EmbeddedPreviewExtractor.shared.extractPreview(from: file)
            }).value {
                previewSize = "\(Int(image.size.width))x\(Int(image.size.height))"
            }
            */
            previewSize = "Skipped"
            
            print(String(format: "%-20s | %-10s | %-10s | %-15s", file.lastPathComponent, cgOrient, exifOrient, previewSize))
        }
        print("=================================\n")
    }
}
