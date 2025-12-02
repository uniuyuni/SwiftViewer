import XCTest
import Foundation

final class ExifRawTest: XCTestCase {
    
    func testExifRawJSON() throws {
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
        
        print("\n=== EXIF RAW JSON DEBUG ===")
        print("File: \(file.lastPathComponent)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/exiftool")
        // Use -n to match v1.56
        process.arguments = ["-j", "-n", "-g", "-struct", file.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let jsonString = String(data: data, encoding: .utf8) {
            print("JSON Output:")
            print(jsonString)
        } else {
            print("❌ Failed to read JSON output")
        }
        print("==================\n")
    }
}
