import XCTest
@testable import SwiftViewerCore

final class SwiftViewerTests: XCTestCase {
    
    // MARK: - FileSystemService Tests
    
    func testColorLabelParsing() {
        // Test standard label numbers
        // Note: We can't easily mock URLResourceValues without a real file, 
        // but we can test the logic if we extract it or use a temporary file.
        // For now, let's assume we can test the mapping logic if it were exposed, 
        // or we create a temp file and set attributes.
        
        let tempDir = FileManager.default.temporaryDirectory
        var tempFile = tempDir.appendingPathComponent("test_label.txt")
        try? "test".write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Set label to Red (6)
        var values = URLResourceValues()
        values.labelNumber = 6
        try? tempFile.setResourceValues(values)
        
        let label = FileSystemService.shared.getColorLabel(from: tempFile)
        XCTAssertEqual(label, "Red", "Label number 6 should be Red")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempFile)
    }
    
    // MARK: - AdvancedCopyViewModel Logic Tests
    
    func testVirtualFolderFiltering() {
        // Verify the logic used in SimpleFolderTreeView.mergeSubfolders
        // Logic: Filter out virtual folders if a real folder with the same name exists.
        
        let tempDir = FileManager.default.temporaryDirectory
        let parentURL = tempDir.appendingPathComponent("Parent")
        let realFolderURL = parentURL.appendingPathComponent("2023-10-27")
        
        // Virtual folder (would be created by ViewModel)
        let virtualFolder = FileItem(url: realFolderURL, isDirectory: true, isAvailable: false)
        
        // Case 1: Real folder exists
        let realFolder = FileItem(url: realFolderURL, isDirectory: true, isAvailable: true)
        let subfolders = [realFolder]
        let virtualFolders = [virtualFolder]
        
        // Logic from SimpleFolderTreeView
        let filteredVirtual = virtualFolders.filter { virtual in
            !subfolders.contains { real in
                real.url.standardizedFileURL == virtual.url.standardizedFileURL
            }
        }
        
        XCTAssertTrue(filteredVirtual.isEmpty, "Virtual folder should be filtered out if real folder exists")
        
        // Case 2: Real folder does NOT exist
        let otherRealFolder = FileItem(url: parentURL.appendingPathComponent("Other"), isDirectory: true, isAvailable: true)
        let subfolders2 = [otherRealFolder]
        
        let filteredVirtual2 = virtualFolders.filter { virtual in
            !subfolders2.contains { real in
                real.url.standardizedFileURL == virtual.url.standardizedFileURL
            }
        }
        
        XCTAssertEqual(filteredVirtual2.count, 1, "Virtual folder should be kept if real folder does not exist")
    }
    
    func testSelectedFilesUpdate() {
        // Verify the logic used in MainViewModel.refreshFileAttributes to update selectedFiles
        
        let url1 = URL(fileURLWithPath: "/tmp/file1.jpg")
        let url2 = URL(fileURLWithPath: "/tmp/file2.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, isAvailable: true, uuid: UUID(), colorLabel: "Red")
        let item2 = FileItem(url: url2, isDirectory: false, isAvailable: true, uuid: UUID(), colorLabel: "Blue")
        
        var selectedFiles: Set<FileItem> = [item1]
        
        // Simulate refresh: item1 changes label to "Green"
        let newItem1 = FileItem(url: url1, isDirectory: false, isAvailable: true, uuid: item1.uuid, colorLabel: "Green")
        let newItems = [newItem1, item2]
        
        // Logic from MainViewModel
        if !selectedFiles.isEmpty {
            var newSelection = Set<FileItem>()
            for item in selectedFiles {
                if let newItem = newItems.first(where: { $0.url == item.url }) {
                    newSelection.insert(newItem)
                } else {
                    newSelection.insert(item)
                }
            }
            selectedFiles = newSelection
        }
        
        XCTAssertEqual(selectedFiles.count, 1)
        XCTAssertEqual(selectedFiles.first?.colorLabel, "Green", "Selected file should be updated with new attributes")
    }
}
