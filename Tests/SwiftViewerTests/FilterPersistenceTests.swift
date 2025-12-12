
import XCTest
@testable import SwiftViewerCore
import CoreData

@MainActor
final class FilterPersistenceTests: XCTestCase {
    var persistenceController: PersistenceController!
    var viewModel: MainViewModel!
    var tempDir: URL!
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController(inMemory: true)
        viewModel = MainViewModel(persistenceController: persistenceController, inMemory: true)
        
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true, attributes: nil)
        tempDir = tempBase.resolvingSymlinksInPath()
        
        viewModel.appMode = .folders
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testFilterPersistenceAcrossFolderChange() async throws {
        // 1. Setup initial state
        // Set a Value (Selection)
        viewModel.filterCriteria.selectedMakers.insert("Canon")
        // Set a Layout (Visible Columns)
        viewModel.filterCriteria.visibleColumns = [.maker, .lens, .iso]
        
        // 2. Simulate opening a folder
        let folderItem = FileItem(url: tempDir, isDirectory: true)
        viewModel.openFolder(folderItem)
        
        // Wait for potential async operations
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // 3. Verify behavior:
        // Layout (Columns) SHOULD persist
        XCTAssertEqual(viewModel.filterCriteria.visibleColumns, [.maker, .lens, .iso], "Visible Columns (Layout) should persist")
        
        // Values (Selection) SHOULD be reset
        XCTAssertTrue(viewModel.filterCriteria.selectedMakers.isEmpty, "Selected Makers (Values) should be reset")
        
        
        // 4. Simulate opening another folder
        let subDir = tempDir.appendingPathComponent("SubDir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let subFolderItem = FileItem(url: subDir, isDirectory: true)
        
        // 5. Setup again for second check
        viewModel.filterCriteria.selectedMakers.insert("Nikon")
        viewModel.filterCriteria.visibleColumns = [.date, .shutterSpeed]
        
        viewModel.openFolder(subFolderItem)
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // 6. Verify again
        XCTAssertEqual(viewModel.filterCriteria.visibleColumns, [.date, .shutterSpeed], "Visible Columns should persist across folder switch")
        XCTAssertTrue(viewModel.filterCriteria.selectedMakers.isEmpty, "Selected Makers should be reset across folder switch")
    }
    
    func testFilterPersistenceThroughSerialization() throws {
        // 1. Set filters
        var criteria = FilterCriteria()
        criteria.selectedMakers.insert("Nikon")
        criteria.visibleColumns = [.maker, .lens]
        
        // 2. Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)
        
        // 3. Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilterCriteria.self, from: data)
        
        // 4. Verify
        XCTAssertTrue(decoded.selectedMakers.contains("Nikon"))
        XCTAssertEqual(decoded.visibleColumns, [.maker, .lens])
    }
}
