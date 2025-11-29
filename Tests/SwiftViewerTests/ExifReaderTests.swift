import XCTest
@testable import SwiftViewerCore

final class ExifReaderTests: XCTestCase {
    
    func testReadExifMissingFile() async {
        let url = URL(fileURLWithPath: "/path/to/missing/file.jpg")
        let metadata = await ExifReader.shared.readExif(from: url)
        XCTAssertNil(metadata, "Metadata should be nil for missing file")
    }
    
    func testLogFileCreation() async {
        // Trigger a log by calling readExif with a missing file (which logs "ExifTool not found" or similar if it tries fallback)
        // Actually, ExifReader logs "ExifTool not found" if the binary is missing, or "ExifTool failed" if run fails.
        // Let's try to trigger a log.
        
        let url = URL(fileURLWithPath: "/tmp/test_image.jpg")
        _ = await ExifReader.shared.readExif(from: url)
        
        // Check if log file exists
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            XCTFail("Could not find Documents directory")
            return
        }
        let logFileURL = documents.appendingPathComponent("SwiftViewer_Log.txt")
        
        let exists = FileManager.default.fileExists(atPath: logFileURL.path)
        XCTAssertTrue(exists, "Log file should exist after logging")
        
        // Optional: Check content
        if let content = try? String(contentsOf: logFileURL) {
            print("Log Content: \(content)")
            XCTAssertFalse(content.isEmpty, "Log file should not be empty")
        }
    }
}
