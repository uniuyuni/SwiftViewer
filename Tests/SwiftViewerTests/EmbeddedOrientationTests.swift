import XCTest
@testable import SwiftViewerCore
import ImageIO

final class EmbeddedOrientationTests: XCTestCase {
    
    func testDumpEmbeddedOrientation() async throws {
        throw XCTSkip("Skipping manual debug test")
        /*
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let testfilesURL = currentDirectory.appendingPathComponent("Testfiles")
        
        guard fileManager.fileExists(atPath: testfilesURL.path) else { return }
        
        let files = try fileManager.contentsOfDirectory(at: testfilesURL, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        print("\n=== EMBEDDED PREVIEW ORIENTATION DEBUG ===")
        print(String(format: "%-20s | %-10s | %-10s | %-10s", "Filename", "RAW Orient", "Embed Orient", "NSImage Size"))
        print(String(repeating: "-", count: 65))
        
        for file in files {
            // 1. RAW Orientation (from CGImageSource)
            var rawOrient = "N/A"
            if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
               let orient = props[kCGImagePropertyOrientation as String] as? Int {
                rawOrient = "\(orient)"
            }
            
            // 2. Extract Embedded Data Orientation via Shell Pipe
            var embedOrient = "N/A"
            let nsImageSize = "N/A"
            
            let pipeCommand = "exiftool -b -PreviewImage \"\(file.path)\" | exiftool -Orientation -n -"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", pipeCommand]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                // Output format: "Orientation : 1" or just "1" if -n used?
                // With -n and -Orientation, it usually prints "Orientation : 1"
                // Let's parse it.
                if let range = output.range(of: ": ") {
                    embedOrient = String(output[range.upperBound...])
                } else {
                    embedOrient = output // Maybe just number if -s -s -n?
                }
            }
            
            // Check JpgFromRaw if PreviewImage failed (empty output)
            if embedOrient.isEmpty || embedOrient == "N/A" {
                 // let pipeCommand2 = "exiftool -b -JpgFromRaw \"\(file.path)\" | exiftool -Orientation -n -"
                 // ... simplify for now, just mark as checked
                 embedOrient = "TryJpg"
            }
            
            print(String(format: "%-20s | %-10s | %-10s | %-10s", file.lastPathComponent, rawOrient, embedOrient, nsImageSize))
        }
        print("==========================================\n")
        */
    }
}
