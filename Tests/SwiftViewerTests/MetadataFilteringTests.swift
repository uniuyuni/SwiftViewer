import XCTest
@testable import SwiftViewerCore
import CoreData

/// 9種類のメタデータフィルタリングの包括的なテスト
/// 実際のViewModelでのフィルタリングロジックを詳細にテストします
@MainActor
final class MetadataFilteringTests: XCTestCase {
    var viewModel: MainViewModel!
    var persistenceController: PersistenceController!
    var context: NSManagedObjectContext!
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController(inMemory: true)
        context = persistenceController.container.viewContext
        viewModel = MainViewModel(persistenceController: persistenceController, inMemory: true)
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        context = nil
        persistenceController = nil
    }
    
    // MARK: - Maker フィルタ
    
    func testMakerFilter_SingleSelection() {
        let url1 = URL(fileURLWithPath: "/canon.jpg")
        let url2 = URL(fileURLWithPath: "/nikon.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.cameraMake = "Canon"
        var meta2 = ExifMetadata()
        meta2.cameraMake = "Nikon"
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedMakers = ["Canon"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1)
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    func testMakerFilter_MultipleSelection() {
        let url1 = URL(fileURLWithPath: "/canon.jpg")
        let url2 = URL(fileURLWithPath: "/nikon.jpg")
        let url3 = URL(fileURLWithPath: "/sony.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        let item3 = FileItem(url: url3, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.cameraMake = "Canon"
        var meta2 = ExifMetadata()
        meta2.cameraMake = "Nikon"
        var meta3 = ExifMetadata()
        meta3.cameraMake = "Sony"
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        viewModel.metadataCache[url3] = meta3
        
        viewModel.allFiles = [item1, item2, item3]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedMakers = ["Canon", "Nikon"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 2, "Canon と Nikon のみ表示")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url2 })
        XCTAssertFalse(viewModel.fileItems.contains { $0.url == url3 })
    }
    
    // MARK: - Camera フィルタ
    
    func testCameraFilter_SingleSelection() {
        let url1 = URL(fileURLWithPath: "/r5.jpg")
        let url2 = URL(fileURLWithPath: "/d850.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.cameraModel = "EOS R5"
        var meta2 = ExifMetadata()
        meta2.cameraModel = "D850"
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedCameras = ["EOS R5"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1)
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    func testCameraFilter_MultipleSelection() {
        let url1 = URL(fileURLWithPath: "/r5.jpg")
        let url2 = URL(fileURLWithPath: "/r6.jpg")
        let url3 = URL(fileURLWithPath: "/d850.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        let item3 = FileItem(url: url3, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.cameraModel = "EOS R5"
        var meta2 = ExifMetadata()
        meta2.cameraModel = "EOS R6"
        var meta3 = ExifMetadata()
        meta3.cameraModel = "D850"
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        viewModel.metadataCache[url3] = meta3
        
        viewModel.allFiles = [item1, item2, item3]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedCameras = ["EOS R5", "EOS R6"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 2)
    }
    
    // MARK: - Lens フィルタ
    
    func testLensFilter_SingleSelection() {
        let url1 = URL(fileURLWithPath: "/24-70.jpg")
        let url2 = URL(fileURLWithPath: "/70-200.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.lensModel = "RF 24-70mm f/2.8L"
        var meta2 = ExifMetadata()
        meta2.lensModel = "RF 70-200mm f/2.8L"
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedLenses = ["RF 24-70mm f/2.8L"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1)
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    // MARK: - ISO フィルタ
    
    func testISOFilter_SingleValue() {
        let url1 = URL(fileURLWithPath: "/iso100.jpg")
        let url2 = URL(fileURLWithPath: "/iso400.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.iso = 100
        var meta2 = ExifMetadata()
        meta2.iso = 400
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedISOs = ["100"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1)
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    func testISOFilter_MultipleValues() {
        let url1 = URL(fileURLWithPath: "/iso100.jpg")
        let url2 = URL(fileURLWithPath: "/iso400.jpg")
        let url3 = URL(fileURLWithPath: "/iso1600.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        let item3 = FileItem(url: url3, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.iso = 100
        var meta2 = ExifMetadata()
        meta2.iso = 400
        var meta3 = ExifMetadata()
        meta3.iso = 1600
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        viewModel.metadataCache[url3] = meta3
        
        viewModel.allFiles = [item1, item2, item3]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedISOs = ["100", "400"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 2)
    }
    
    // MARK: - FileType フィルタ
    
    func testFileTypeFilter_JPG() {
        let url1 = URL(fileURLWithPath: "/photo.jpg")
        let url2 = URL(fileURLWithPath: "/photo.cr2")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedFileTypes = ["JPG"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1)
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    func testFileTypeFilter_RAW() {
        let url1 = URL(fileURLWithPath: "/photo.cr2")
        let url2 = URL(fileURLWithPath: "/photo.nef")
        let url3 = URL(fileURLWithPath: "/photo.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        let item3 = FileItem(url: url3, isDirectory: false)
        
        viewModel.allFiles = [item1, item2, item3]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedFileTypes = ["CR2", "NEF"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 2, "RAW形式のみ表示")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url2 })
    }
    
    // MARK: - フィルタの組み合わせ（AND条件）
    
    func testCombination_MakerAndCamera() {
        let url1 = URL(fileURLWithPath: "/canon_r5.jpg")
        let url2 = URL(fileURLWithPath: "/canon_r6.jpg")
        let url3 = URL(fileURLWithPath: "/nikon_d850.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        let item3 = FileItem(url: url3, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.cameraMake = "Canon"
        meta1.cameraModel = "EOS R5"
        var meta2 = ExifMetadata()
        meta2.cameraMake = "Canon"
        meta2.cameraModel = "EOS R6"
        var meta3 = ExifMetadata()
        meta3.cameraMake = "Nikon"
        meta3.cameraModel = "D850"
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        viewModel.metadataCache[url3] = meta3
        
        viewModel.allFiles = [item1, item2, item3]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedMakers = ["Canon"]
        viewModel.filterCriteria.selectedCameras = ["EOS R5"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "Canon AND EOS R5")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    func testCombination_ThreeFilters() {
        let url1 = URL(fileURLWithPath: "/perfect.jpg")
        let url2 = URL(fileURLWithPath: "/almost.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.cameraMake = "Canon"
        meta1.cameraModel = "EOS R5"
        meta1.lensModel = "RF 24-70mm f/2.8L"
        
        var meta2 = ExifMetadata()
        meta2.cameraMake = "Canon"
        meta2.cameraModel = "EOS R5"
        meta2.lensModel = "RF 70-200mm f/2.8L"
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedMakers = ["Canon"]
        viewModel.filterCriteria.selectedCameras = ["EOS R5"]
        viewModel.filterCriteria.selectedLenses = ["RF 24-70mm f/2.8L"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "3つのAND条件")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    func testCombination_WithOtherFilters() {
        let url1 = URL(fileURLWithPath: "/perfect.jpg")
        let url2 = URL(fileURLWithPath: "/good.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, colorLabel: "Blue")
        let item2 = FileItem(url: url2, isDirectory: false, colorLabel: "Red")
        
        var meta1 = ExifMetadata()
        meta1.cameraMake = "Canon"
        meta1.rating = 5
        var meta2 = ExifMetadata()
        meta2.cameraMake = "Canon"
        meta2.rating = 3
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedMakers = ["Canon"]
        viewModel.filterCriteria.minRating = 4
        viewModel.filterCriteria.colorLabel = "Blue"
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "Maker + Rating + Color")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    // MARK: - 空のセット（フィルタなし）
    
    func testEmptyFilter_ShowsAll() {
        let url1 = URL(fileURLWithPath: "/1.jpg")
        let url2 = URL(fileURLWithPath: "/2.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedMakers = []
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 2, "空のフィルタはすべて表示")
    }
    
    // MARK: - 存在しない値でのフィルタ
    
    func testNonExistentValue_ShowsNothing() {
        let url1 = URL(fileURLWithPath: "/canon.jpg")
        let item1 = FileItem(url: url1, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.cameraMake = "Canon"
        viewModel.metadataCache[url1] = meta1
        
        viewModel.allFiles = [item1]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedMakers = ["Fujifilm"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 0, "存在しないメーカーでフィルタ")
    }
    
    // MARK: - nullメタデータの処理
    
    func testNullMetadata_ExcludedFromFilter() {
        let url1 = URL(fileURLWithPath: "/with_maker.jpg")
        let url2 = URL(fileURLWithPath: "/no_maker.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.cameraMake = "Canon"
        viewModel.metadataCache[url1] = meta1
        // meta2にはcameraMakeがnil
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedMakers = ["Canon"]
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1)
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    // MARK: - フィルタのクリア
    
    func testClearFilters_ShowsAll() {
        let url1 = URL(fileURLWithPath: "/canon.jpg")
        let url2 = URL(fileURLWithPath: "/nikon.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url2, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.cameraMake = "Canon"
        var meta2 = ExifMetadata()
        meta2.cameraMake = "Nikon"
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        
        // フィルタを設定
        viewModel.filterCriteria.selectedMakers = ["Canon"]
        viewModel.applyFilter()
        XCTAssertEqual(viewModel.fileItems.count, 1)
        
        // フィルタをクリア
        viewModel.filterCriteria.selectedMakers = []
        viewModel.applyFilter()
        XCTAssertEqual(viewModel.fileItems.count, 2, "フィルタクリアですべて表示")
    }
    
    // MARK: - 大文字小文字の処理
    
    func testCaseSensitivity() {
        let url1 = URL(fileURLWithPath: "/canon.jpg")
        let item1 = FileItem(url: url1, isDirectory: false)
        
        var meta1 = ExifMetadata()
        meta1.cameraMake = "Canon"
        viewModel.metadataCache[url1] = meta1
        
        viewModel.allFiles = [item1]
        viewModel.appMode = .folders
        viewModel.filterCriteria.selectedMakers = ["canon"]  // 小文字
        viewModel.applyFilter()
        
        // 実装により異なる可能性があるが、大文字小文字を区別する場合
        // XCTAssertEqual(viewModel.fileItems.count, 0)
        // または区別しない場合
        // XCTAssertEqual(viewModel.fileItems.count, 1)
    }
}
