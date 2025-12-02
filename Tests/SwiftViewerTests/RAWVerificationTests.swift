import XCTest
@testable import SwiftViewerCore

final class RAWVerificationTests: XCTestCase {
    
    func testRAWThumbnailGeneration() async throws {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let testfilesURL = currentDirectory.appendingPathComponent("Testfiles")
        
        print("Looking for Testfiles at: \(testfilesURL.path)")
        
        guard fileManager.fileExists(atPath: testfilesURL.path) else {
            XCTFail("Testfiles directory not found at \(testfilesURL.path). Please ensure it exists.")
            return
        }
        
        let files = try fileManager.contentsOfDirectory(at: testfilesURL, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") } // Skip hidden files
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        print("Found \(files.count) files in Testfiles.")
        
        var successCount = 0
        var failureCount = 0
        var failures: [String] = []
        
        for file in files {
            print("Testing: \(file.lastPathComponent)")
            
            // Use a reasonable size for thumbnail
            let size = CGSize(width: 300, height: 300)
            
            // Measure time
            let start = Date()
            
            // Debug Rotation Metadata
            var cgOrient = "N/A"
            if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
               let orient = props[kCGImagePropertyOrientation as String] as? Int {
                cgOrient = "\(orient)"
            }
            
            var exifOrient = "N/A"
            if let meta = ExifReader.shared.readExifUsingExifTool(from: file),
               let orient = meta.orientation {
                exifOrient = "\(orient)"
            }
            
            print("  ℹ️ Rotation Debug: CG=\(cgOrient), Exif=\(exifOrient)")

            let image = await ThumbnailGenerator.shared.generateThumbnail(for: file, size: size)
            let duration = Date().timeIntervalSince(start)

            if let img = image, img.size.width > 0, img.size.height > 0 {
                print("  ✅ Success: \(Int(img.size.width))x\(Int(img.size.height)) (took \(String(format: "%.2f", duration))s)")
                successCount += 1
            } else {
                print("  ❌ Failed: No image generated or size is 0x0")
                failureCount += 1
                failures.append(file.lastPathComponent)
            }
        }
        
        print("\n--- Summary ---")
        print("Total: \(files.count)")
        print("Success: \(successCount)")
        print("Failed: \(failureCount)")
        
        if failureCount > 0 {
            print("Failed files: \(failures)")
            XCTFail("Failed to generate thumbnails for \(failureCount) RAW files.")
        }
    }
    
    func testExifToolAvailability() {
        let path = "/usr/local/bin/exiftool"
        let exists = FileManager.default.fileExists(atPath: path)
        print("ExifTool at \(path): \(exists ? "Found" : "Not Found")")
        
        if !exists {
            // Check PATH
            let process = Process()
            process.launchPath = "/usr/bin/which"
            process.arguments = ["exiftool"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.launch()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                print("ExifTool found in PATH at: \(path)")
            } else {
                print("ExifTool not found in PATH.")
            }
        }
    }
}
