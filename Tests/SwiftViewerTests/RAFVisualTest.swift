import XCTest
import AppKit
@testable import SwiftViewerCore

final class RAFVisualTest: XCTestCase {
    
    func testRAFVisuals() async throws {
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
        
        print("\n=== RAF VISUAL DEBUG ===")
        print("File: \(file.lastPathComponent)")
        
        // 1. Check EXIF Dimensions
        if let meta = ExifReader.shared.readExifUsingExifTool(from: file) {
            print("  ✅ ExifTool Read:")
            print("     Orientation: \(meta.orientation ?? -1)")
            print("     Width: \(meta.width ?? -1)")
            print("     Height: \(meta.height ?? -1)")
            if let w = meta.width, let h = meta.height {
                if w > h { print("     Result: Landscape (Width > Height)") }
                else { print("     Result: Portrait (Height > Width)") }
            }
        } else {
            print("  ❌ ExifTool Failed")
        }
        
        // 2. Generate Thumbnail
        // We need to initialize ThumbnailGenerator (it uses singleton, but we can just use it)
        // Note: ThumbnailGenerator uses MainActor for some things? No, mostly background.
        
        let gen = ThumbnailGenerator.shared
        let size = CGSize(width: 300, height: 300)
        
        print("  Generating Thumbnail...")
        if let thumb = await gen.generateThumbnail(for: file, size: size) {
            print("  ✅ Thumbnail Generated")
            print("     Size: \(thumb.size)")
            
            // Save to disk
            let saveURL = currentDirectory.appendingPathComponent("RAF_Debug.jpg")
            if let tiffData = thumb.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpgData = bitmap.representation(using: .jpeg, properties: [:]) {
                try jpgData.write(to: saveURL)
                print("     Saved to: \(saveURL.path)")
            }
        } else {
            print("  ❌ Thumbnail Generation Failed")
        }
        
        print("==================\n")
    }
}
