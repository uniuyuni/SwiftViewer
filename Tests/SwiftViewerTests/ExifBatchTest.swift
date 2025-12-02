import XCTest
@testable import SwiftViewerCore

final class ExifBatchTest: XCTestCase {
    func testRAFBatchDimensions() async throws {
        // Use the known RAF file
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: cwd).appendingPathComponent("Testfiles/_DSF2424.RAF")
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Skipping testRAFBatchDimensions: File not found at \(url.path)")
            return
        }
        
        // Run batch read
        let results = await ExifReader.shared.readExifBatch(from: [url])
        
        guard let meta = results[url] else {
            XCTFail("No metadata returned for RAF")
            return
        }
        
        print("DEBUG: Batch Meta Width: \(meta.width ?? -1), Height: \(meta.height ?? -1), Orientation: \(meta.orientation ?? -1)")
        
        // Expect Portrait dimensions (swapped)
        // Original: 5184x7752 (Landscape-ish raw)
        // Orientation 8 -> Should swap to 7752x5184?
        // Wait, current fix says:
        // RAF is Portrait (2944x4416) visually.
        // Metadata says Orient 8.
        // If we swap, we get Portrait dimensions.
        // 5184 (W) x 7752 (H).
        // If Orient 8, we swap -> W=7752, H=5184.
        // Wait.
        // Let's check what `readExifUsingExifTool` returns.
        
        // In previous test:
        // Width: 5184, Height: 7752.
        // Result: Portrait (Height > Width).
        // This means W=5184, H=7752.
        // And Orient 8.
        // If Orient 8, we swap?
        // If raw W=5184, H=7752.
        // If Orient 8 (Rotate 270 CW), then Visual Width = 7752, Visual Height = 5184. (Landscape).
        
        // BUT user says "RAF is Portrait image".
        // And "EXIF(Dimensions) not rotated".
        // If user sees 5184x7752, that IS Portrait.
        // If user sees 7752x5184, that is Landscape.
        
        // User says "EXIF(Dimensions) not rotated when vertical image".
        // This usually means they see the "Physical" dimensions (Landscape) instead of "Visual" (Portrait).
        // So they see 7752x5184 (or whatever the sensor size is).
        // And they WANT 5184x7752.
        
        // So we EXPECT Width < Height.
        
        XCTAssertTrue((meta.width ?? 0) < (meta.height ?? 0), "Width should be less than Height for Portrait RAF")
    }
    
    func testRAFSingleReadDimensions() async throws {
        // Use the known RAF file
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: cwd).appendingPathComponent("Testfiles/_DSF2424.RAF")
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Skipping testRAFSingleReadDimensions: File not found at \(url.path)")
            return
        }
        
        // Run single read (force ExifTool path)
        // We can't easily force readExifUsingExifTool because it's internal.
        // But readExif calls _readExif which calls readExifUsingExifTool for RAW.
        
        let meta = await ExifReader.shared.readExif(from: url)
        
        guard let meta = meta else {
            XCTFail("No metadata returned for RAF (Single)")
            return
        }
        
        print("DEBUG: Single Meta Width: \(meta.width ?? -1), Height: \(meta.height ?? -1), Orientation: \(meta.orientation ?? -1)")
        
        XCTAssertTrue((meta.width ?? 0) < (meta.height ?? 0), "Width should be less than Height for Portrait RAF (Single)")
    }
}
