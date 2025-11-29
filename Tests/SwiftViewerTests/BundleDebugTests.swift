import XCTest
@testable import SwiftViewerCore

class BundleDebugTests: XCTestCase {
    func testBundleIdentifier() async {
        // This test just ensures we can access the bundle
        let bundleID = Bundle.main.bundleIdentifier
        print("Bundle ID: \(bundleID ?? "nil")")
        
        // Trigger a log by calling readExif with a missing file (which logs "ExifTool not found" or similar if it tries fallback)
        // Actually, ExifReader logs "ExifTool not found" if the binary is missing, or "ExifTool failed" if run fails.
        
        let url = URL(fileURLWithPath: "/tmp/test_image.jpg")
        _ = await ExifReader.shared.readExif(from: url)
        
        // Check if log file exists
        // let logURL = Logger.shared.logFileURL
        // XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))
    }
}
