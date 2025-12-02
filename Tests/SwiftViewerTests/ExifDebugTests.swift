import XCTest
@testable import SwiftViewerCore

final class ExifDebugTests: XCTestCase {
    
    func testReadExif() async throws {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let testfilesURL = currentDirectory.appendingPathComponent("Testfiles")
        
        guard fileManager.fileExists(atPath: testfilesURL.path) else { return }
        
        let files = try fileManager.contentsOfDirectory(at: testfilesURL, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        print("\n=== EXIF DEBUG ===")
        
        for file in files {
            print("Processing: \(file.lastPathComponent)")
            
            // 1. Try Sync Read
            if let meta = ExifReader.shared.readExifSync(from: file) {
                print("  ✅ readExifSync: Make=\(meta.cameraMake ?? "nil"), Model=\(meta.cameraModel ?? "nil"), Orient=\(meta.orientation ?? -1)")
            } else {
                print("  ❌ readExifSync: Failed")
            }
            
            // 2. Try ExifTool Direct
            if let meta = ExifReader.shared.readExifUsingExifTool(from: file) {
                print("  ✅ ExifTool: Make=\(meta.cameraMake ?? "nil"), Model=\(meta.cameraModel ?? "nil"), Orient=\(meta.orientation ?? -1)")
            } else {
                print("  ❌ ExifTool: Failed")
            }
        }
        
        print("\n=== BATCH TEST ===")
        let batchResult = await ExifReader.shared.readExifBatch(from: files)
        print("Batch Read Count: \(batchResult.count) / \(files.count)")
        for file in files {
            if let meta = batchResult[file] {
                print("  ✅ Batch: \(file.lastPathComponent) -> Make=\(meta.cameraMake ?? "nil")")
            } else {
                print("  ❌ Batch: \(file.lastPathComponent) -> Missing")
            }
        }
        
        print("==================\n")
    }
}
