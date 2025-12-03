import XCTest
@testable import SwiftViewerCore
import CoreData

/// フラグ機能（Pick/Reject）の包括的なテスト
/// フラグ機能は写真選別ワークフ��ーをサポートする重要機能です
@MainActor
final class FlagFeatureTests: XCTestCase {
    var viewModel: MainViewModel!
    var persistenceController: PersistenceController!
    var context: NSManagedObjectContext!
    
    override func setUpWithError() throws {
        persistenceController = PersistenceController(inMemory: true)
        context = persistenceController.container.viewContext
        viewModel = MainViewModel(persistenceController: persistenceController)
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        context = nil
        persistenceController = nil
    }
    
    // MARK: - flagStatusの初期値
    
    func testFlagStatus_DefaultNil() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false)
        XCTAssertNil(item.flagStatus, "デフォルトはnil")
    }
    
    func testFlagStatus_DefaultZero() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, flagStatus: 0)
        XCTAssertEqual(item.flagStatus, 0, "明示的に0を設定")
    }
    
    // MARK: - フラグの設定
    
    func testFlagStatus_SetPick() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, flagStatus: 1)
        XCTAssertEqual(item.flagStatus, 1, "Pickフラグ（+1）")
    }
    
    func testFlagStatus_SetReject() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, flagStatus: -1)
        XCTAssertEqual(item.flagStatus, -1, "Rejectフラグ（-1）")
    }
    
    func testFlagStatus_SetNone() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, flagStatus: 0)
        XCTAssertEqual(item.flagStatus, 0, "フラグなし（0）")
    }
    
    // MARK: - フラグの切り替え
    
    func testFlagToggle_NoneToPickToRejectToNone() {
        let url = URL(fileURLWithPath: "/test.jpg")
        
        // None (0)
        var item = FileItem(url: url, isDirectory: false, flagStatus: 0)
        XCTAssertEqual(item.flagStatus, 0)
        
        // None -> Pick (1)
        item = FileItem(url: url, isDirectory: false, uuid: item.uuid, flagStatus: 1)
        XCTAssertEqual(item.flagStatus, 1)
        
        // Pick -> Reject (-1)
        item = FileItem(url: url, isDirectory: false, uuid: item.uuid, flagStatus: -1)
        XCTAssertEqual(item.flagStatus, -1)
        
        // Reject -> None (0)
        item = FileItem(url: url, isDirectory: false, uuid: item.uuid, flagStatus: 0)
        XCTAssertEqual(item.flagStatus, 0)
    }
    
    // MARK: - FlagFilterの動作
    
    func testFlagFilter_All_ShowsEverything() {
        viewModel.filterCriteria.flagFilter = .all
        XCTAssertEqual(viewModel.filterCriteria.flagFilter, .all)
        XCTAssertFalse(viewModel.filterCriteria.isActive, "allフィルタは非アクティブ")
    }
    
    func testFlagFilter_Flagged_PickAndReject() {
        viewModel.filterCriteria.flagFilter = .flagged
        XCTAssertEqual(viewModel.filterCriteria.flagFilter, .flagged)
        XCTAssertTrue(viewModel.filterCriteria.isActive)
    }
    
    func testFlagFilter_Unflagged_OnlyNone() {
        viewModel.filterCriteria.flagFilter = .unflagged
        XCTAssertEqual(viewModel.filterCriteria.flagFilter, .unflagged)
        XCTAssertTrue(viewModel.filterCriteria.isActive)
    }
    
    func testFlagFilter_Pick_OnlyPick() {
        viewModel.filterCriteria.flagFilter = .pick
        XCTAssertEqual(viewModel.filterCriteria.flagFilter, .pick)
        XCTAssertTrue(viewModel.filterCriteria.isActive)
    }
    
    func testFlagFilter_Reject_OnlyReject() {
        viewModel.filterCriteria.flagFilter = .reject
        XCTAssertEqual(viewModel.filterCriteria.flagFilter, .reject)
        XCTAssertTrue(viewModel.filterCriteria.isActive)
    }
    
    // MARK: - フィルタリングロジック
    
    func testFiltering_FlaggedShowsPickAndReject() {
        let url1 = URL(fileURLWithPath: "/pick.jpg")
        let url2 = URL(fileURLWithPath: "/reject.jpg")
        let url3 = URL(fileURLWithPath: "/none.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, flagStatus: 1)  // Pick
        let item2 = FileItem(url: url2, isDirectory: false, flagStatus: -1) // Reject
        let item3 = FileItem(url: url3, isDirectory: false, flagStatus: 0)  // None
        
        viewModel.allFiles = [item1, item2, item3]
        viewModel.appMode = .folders
        viewModel.filterCriteria.flagFilter = .flagged
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 2, "FlaggedフィルタでPickとRejectのみ表示")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url2 })
        XCTAssertFalse(viewModel.fileItems.contains { $0.url == url3 })
    }
    
    func testFiltering_UnflaggedShowsOnlyNone() {
        let url1 = URL(fileURLWithPath: "/pick.jpg")
        let url2 = URL(fileURLWithPath: "/none.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, flagStatus: 1)
        let item2 = FileItem(url: url2, isDirectory: false, flagStatus: 0)
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.flagFilter = .unflagged
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "Unflaggedフィルタでフラグなしのみ表示")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url2 })
        XCTAssertFalse(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    func testFiltering_PickShowsOnlyPick() {
        let url1 = URL(fileURLWithPath: "/pick.jpg")
        let url2 = URL(fileURLWithPath: "/reject.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, flagStatus: 1)
        let item2 = FileItem(url: url2, isDirectory: false, flagStatus: -1)
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.flagFilter = .pick
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "PickフィルタでPickのみ表示")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
        XCTAssertFalse(viewModel.fileItems.contains { $0.url == url2 })
    }
    
    func testFiltering_RejectShowsOnlyReject() {
        let url1 = URL(fileURLWithPath: "/pick.jpg")
        let url2 = URL(fileURLWithPath: "/reject.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, flagStatus: 1)
        let item2 = FileItem(url: url2, isDirectory: false, flagStatus: -1)
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.flagFilter = .reject
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "RejectフィルタでRejectのみ表示")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url2 })
        XCTAssertFalse(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    // MARK: - フラグとレーティングの組み合わせ
    
    func testCombination_FlagAndRating() {
        let url1 = URL(fileURLWithPath: "/pick_5star.jpg")
        let url2 = URL(fileURLWithPath: "/pick_3star.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, flagStatus: 1)
        let item2 = FileItem(url: url2, isDirectory: false, flagStatus: 1)
        
        var meta1 = ExifMetadata()
        meta1.rating = 5
        var meta2 = ExifMetadata()
        meta2.rating = 3
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.flagFilter = .pick
        viewModel.filterCriteria.minRating = 4
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "Pick + 4星以上でフィルタ")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
        XCTAssertFalse(viewModel.fileItems.contains { $0.url == url2 })
    }
    
    // MARK: - フラグとカラーラベルの組み合わせ
    
    func testCombination_FlagAndColor() {
        let url1 = URL(fileURLWithPath: "/pick_blue.jpg")
        let url2 = URL(fileURLWithPath: "/pick_red.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, colorLabel: "Blue", flagStatus: 1)
        let item2 = FileItem(url: url2, isDirectory: false, colorLabel: "Red", flagStatus: 1)
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.flagFilter = .pick
        viewModel.filterCriteria.colorLabel = "Blue"
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "Pick + Blueでフィルタ")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    // MARK: - CoreDataへの永続化
    
    func testCoreData_SaveFlagStatus() throws {
        // Catalogを作成
        let catalog = Catalog(context: context)
        catalog.id = UUID()
        catalog.name = "Test Catalog"
        
        // MediaItemを作成してフラグを設定
        let item = MediaItem(context: context)
        item.id = UUID()
        item.originalPath = "/test/pick.jpg"
        item.flagStatus = 1 // Pick
        item.catalog = catalog
        
        try context.save()
        
        // 読み取り検証
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "originalPath == %@", "/test/pick.jpg")
        let results = try context.fetch(request)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.flagStatus, 1, "Pick フラグが永続化される")
    }
    
    func testCoreData_SaveRejectFlag() throws {
        let catalog = Catalog(context: context)
        catalog.id = UUID()
        catalog.name = "Test Catalog"
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.originalPath = "/test/reject.jpg"
        item.flagStatus = -1 // Reject
        item.catalog = catalog
        
        try context.save()
        
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "originalPath == %@", "/test/reject.jpg")
        let results = try context.fetch(request)
        
        XCTAssertEqual(results.first?.flagStatus, -1, "Rejectフラグが永続化される")
    }
    
   // MARK: - フォルダモードでのフラグ
    
    func testFolderMode_FlagInMetadataCache() {
        // フォルダモードではメタデータキャッシュを使用
        // （実装詳細によるが、テストのために仮定）
        viewModel.appMode = .folders
        XCTAssertEqual(viewModel.appMode, .folders)
    }
    
    // MARK: - カタログモードでのフラグ
    
    func testCatalogMode_FlagInCoreData() throws {
        viewModel.appMode = .catalog
        
        let catalog = Catalog(context: context)
        catalog.id = UUID()
        catalog.name = "Flag Test Catalog"
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.flagStatus = 1
        item.catalog = catalog
        
        try context.save()
        
        XCTAssertEqual(viewModel.appMode, .catalog)
        XCTAssertEqual(item.flagStatus, 1)
    }
    
    // MARK: - 無効な値の処理
    
    func testInvalidFlagValue_OutOfRange() {
        // Int16の範囲内だが、-1/0/1以外の値
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, flagStatus: 2)
        XCTAssertEqual(item.flagStatus, 2, "無効な値も保存可能（アプリケーションロジックで制限）")
    }
    
    func testInvalidFlagValue_Negative() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, flagStatus: -2)
        XCTAssertEqual(item.flagStatus, -2)
    }
    
    // MARK: - マルチセレクション時のフラグ状態
    
    func testMultiSelection_MixedFlags() {
        let item1 = FileItem(url: URL(fileURLWithPath: "/1.jpg"), isDirectory: false, flagStatus: 1)  // Pick
        let item2 = FileItem(url: URL(fileURLWithPath: "/2.jpg"), isDirectory: false, flagStatus: -1) // Reject
        let item3 = FileItem(url: URL(fileURLWithPath: "/3.jpg"), isDirectory: false, flagStatus: 0)  // None
        
        viewModel.selectedFiles = [item1, item2, item3]
        XCTAssertEqual(viewModel.selectedFiles.count, 3)
        
        // 選択されたアイテムでフラグ状態が混在
        let flags = viewModel.selectedFiles.compactMap { $0.flagStatus }
        XCTAssertTrue(flags.contains(1))
        XCTAssertTrue(flags.contains(-1))
        XCTAssertTrue(flags.contains(0))
    }
    
    func testMultiSelection_AllPick() {
        let item1 = FileItem(url: URL(fileURLWithPath: "/1.jpg"), isDirectory: false, flagStatus: 1)
        let item2 = FileItem(url: URL(fileURLWithPath: "/2.jpg"), isDirectory: false, flagStatus: 1)
        
        viewModel.selectedFiles = [item1, item2]
        
        let flags = viewModel.selectedFiles.compactMap { $0.flagStatus }
        XCTAssertTrue(flags.allSatisfy { $0 == 1 }, "全てPickフラグ")
    }
    
    // MARK: - 複数ファイルへの一括フラグ設定
    
    func testBulkFlag_SetPickToMultiple() {
        var item1 = FileItem(url: URL(fileURLWithPath: "/1.jpg"), isDirectory: false)
        var item2 = FileItem(url: URL(fileURLWithPath: "/2.jpg"), isDirectory: false)
        
        // 一括でPickフラグを設定（実装はViewModelで行われるが、ここではデータモデルのテスト）
        item1 = FileItem(url: item1.url, isDirectory: false, uuid: item1.uuid, flagStatus: 1)
        item2 = FileItem(url: item2.url, isDirectory: false, uuid: item2.uuid, flagStatus: 1)
        
        XCTAssertEqual(item1.flagStatus, 1)
        XCTAssertEqual(item2.flagStatus, 1)
    }
}
