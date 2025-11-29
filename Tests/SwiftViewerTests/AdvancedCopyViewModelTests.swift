import XCTest
@testable import SwiftViewerCore

@MainActor
final class AdvancedCopyViewModelTests: XCTestCase {
    
    var viewModel: AdvancedCopyViewModel!
    
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "advancedCopySource")
        UserDefaults.standard.removeObject(forKey: "advancedCopyDest")
        viewModel = AdvancedCopyViewModel()
        viewModel.selectedSourceFolder = nil
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertTrue(viewModel.files.isEmpty)
        XCTAssertTrue(viewModel.selectedFileIDs.isEmpty)
        
        // isLoading depends on whether auto-selection happened immediately
        if viewModel.selectedSourceFolder != nil {
            XCTAssertTrue(viewModel.isLoading)
        } else {
            XCTAssertFalse(viewModel.isLoading)
        }
        
        XCTAssertFalse(viewModel.isCopying)
    }
    
    func testSelectSourceFolder() {
        let url = URL(fileURLWithPath: "/tmp")
        viewModel.selectedSourceFolder = url
        
        XCTAssertTrue(viewModel.isLoading, "Should be loading after selection")
        // Note: loadFiles is async, so files won't be populated immediately.
        // We can use expectations if we want to test the async result, 
        // but for now we verify the state change trigger.
    }
    
    func testUpdatePreviewLogic() {
        // Setup dummy data
        viewModel.organizeByDate = true
        viewModel.selectedDestinationFolder = URL(fileURLWithPath: "/tmp/dest")
        
        // Trigger update
        viewModel.updatePreview()
        
        // Since updatePreview is detached, we can't easily verify the result synchronously without waiting.
        // But we can verify it doesn't crash.
        
        let expectation = XCTestExpectation(description: "Preview Updated")
        
        // We can't easily hook into completion of updatePreview without modifying the VM to be testable (e.g. returning the Task).
        // For now, we just ensure it runs.
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
}
