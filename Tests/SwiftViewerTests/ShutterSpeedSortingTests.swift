import XCTest
@testable import SwiftViewerCore
import CoreData

@MainActor
final class ShutterSpeedSortingTests: XCTestCase {
    var viewModel: MainViewModel!
    var persistenceController: PersistenceController!
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController(inMemory: true)
        viewModel = MainViewModel(persistenceController: persistenceController, inMemory: true)
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        persistenceController = nil
    }
    
    func testShutterSpeedSorting() {
        // Arrange
        let speeds = ["1/100", "1/50", "1/1000", "1\"", "0.5", "5\"", "2.5", "10", "1/4"]
        
        var files: [FileItem] = []
        for (index, speed) in speeds.enumerated() {
            let url = URL(fileURLWithPath: "/test_\(index).jpg")
            let item = FileItem(url: url, isDirectory: false)
            files.append(item)
            
            var meta = ExifMetadata()
            meta.shutterSpeed = speed
            viewModel.metadataCache[url] = meta
        }
        
        viewModel.allFiles = files
        
        // Act
        let sortedSpeeds = viewModel.availableShutterSpeeds
        
        // Assert
        // Expected numerical order:
        // 1/1000 (0.001)
        // 1/100  (0.01)
        // 1/50   (0.02)
        // 1/4    (0.25)
        // 0.5    (0.5)
        // 1"     (1.0)
        // 2.5    (2.5)
        // 5"     (5.0)
        // 10     (10.0)
        
        let expected = ["1/1000", "1/100", "1/50", "1/4", "0.5", "1\"", "2.5", "5\"", "10"]
        
        XCTAssertEqual(sortedSpeeds, expected, "Shutter speeds should be sorted numerically")
    }
    
    func testShutterSpeedParsing_MixedFormats() {
         // Arrange
        let speeds = ["1/60", "30", "15\"", "0.3"]
        
        var files: [FileItem] = []
        for (index, speed) in speeds.enumerated() {
            let url = URL(fileURLWithPath: "/test_\(index).jpg")
            let item = FileItem(url: url, isDirectory: false)
            files.append(item)
            
            var meta = ExifMetadata()
            meta.shutterSpeed = speed
            viewModel.metadataCache[url] = meta
        }
        
        viewModel.allFiles = files
        
        // Act
        let sortedSpeeds = viewModel.availableShutterSpeeds
        
        // Expected: 1/60 (0.0166), 0.3, 15" (15), 30
        let expected = ["1/60", "0.3", "15\"", "30"]
        
        XCTAssertEqual(sortedSpeeds, expected)
    }
    
    func testShutterSpeedSorting_WithUnknown() {
        // Arrange
        let url1 = URL(fileURLWithPath: "/1.jpg")
        let url2 = URL(fileURLWithPath: "/2.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.shutterSpeed = "1/100"
        
        // meta2 has nil shutter speed
        var meta2 = ExifMetadata()
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        
        viewModel.allFiles = [item1, item2]
        
        // Act
        let sortedSpeeds = viewModel.availableShutterSpeeds
        
        // Assert: Unknown should be first or handled as implemented (usually first)
        XCTAssertTrue(sortedSpeeds.contains("Unknown"))
        XCTAssertEqual(sortedSpeeds, ["Unknown", "1/100"])
    }
}
