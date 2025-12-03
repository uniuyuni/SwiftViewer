import XCTest
@testable import SwiftViewerCore
import CoreData

/// お気に入り機能の包括的なテスト
/// お気に入り機能は重要なファイルを素早くマークするための機能です
@MainActor
final class FavoriteFeatureTests: XCTestCase {
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
    
    // MARK: - isFavoriteの初期値
    
    func testFavorite_DefaultNil() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false)
        XCTAssertNil(item.isFavorite, "デフォルトはnil")
    }
    
    func testFavorite_DefaultFalse() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, isFavorite: false)
        XCTAssertEqual(item.isFavorite, false, "明示的にfalseを設定")
    }
    
    // MARK: - お気に入りの設定
    
    func testFavorite_SetTrue() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, isFavorite: true)
        XCTAssertEqual(item.isFavorite, true, "お気に入りON")
    }
    
    func testFavorite_SetFalse() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, isFavorite: false)
        XCTAssertEqual(item.isFavorite, false, "お気に入りOFF")
    }
    
    // MARK: - トグル動作
    
    func testFavorite_Toggle() {
        var item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, isFavorite: false)
        XCTAssertEqual(item.isFavorite, false)
        
        // Toggle: false -> true
        item = FileItem(url: item.url, isDirectory: false, uuid: item.uuid, isFavorite: true)
        XCTAssertEqual(item.isFavorite, true)
        
        // Toggle: true -> false
        item = FileItem(url: item.url, isDirectory: false, uuid: item.uuid, isFavorite: false)
        XCTAssertEqual(item.isFavorite, false)
    }
    
    // MARK: - showOnlyFavoritesフィルタ
    
    func testFilter_ShowOnlyFavorites_True() {
        let url1 = URL(fileURLWithPath: "/favorite.jpg")
        let url2 = URL(fileURLWithPath: "/normal.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, isFavorite: true)
        let item2 = FileItem(url: url2, isDirectory: false, isFavorite: false)
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.showOnlyFavorites = true
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "お気に入りのみ表示")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
        XCTAssertFalse(viewModel.fileItems.contains { $0.url == url2 })
    }
    
    func testFilter_ShowOnlyFavorites_False() {
        let url1 = URL(fileURLWithPath: "/favorite.jpg")
        let url2 = URL(fileURLWithPath: "/normal.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, isFavorite: true)
        let item2 = FileItem(url: url2, isDirectory: false, isFavorite: false)
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.showOnlyFavorites = false
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 2, "すべて表示")
    }
    
    func testFilter_ShowOnlyFavorites_WithNilValues() {
        let url1 = URL(fileURLWithPath: "/favorite.jpg")
        let url2 = URL(fileURLWithPath: "/nil.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, isFavorite: true)
        let item2 = FileItem(url: url2, isDirectory: false, isFavorite: nil)
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.showOnlyFavorites = true
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "nil値はお気に入りでないとして扱う")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    // MARK: - お気に入りとレーティングの組み合わせ
    
    func testCombination_FavoriteAndRating() {
        let url1 = URL(fileURLWithPath: "/fav_5star.jpg")
        let url2 = URL(fileURLWithPath: "/fav_3star.jpg")
        let url3 = URL(fileURLWithPath: "/normal_5star.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, isFavorite: true)
        let item2 = FileItem(url: url2, isDirectory: false, isFavorite: true)
        let item3 = FileItem(url: url3, isDirectory: false, isFavorite: false)
        
        var meta1 = ExifMetadata()
        meta1.rating = 5
        var meta2 = ExifMetadata()
        meta2.rating = 3
        var meta3 = ExifMetadata()
        meta3.rating = 5
        
        viewModel.metadataCache[url1] = meta1
        viewModel.metadataCache[url2] = meta2
        viewModel.metadataCache[url3] = meta3
        
        viewModel.allFiles = [item1, item2, item3]
        viewModel.appMode = .folders
        viewModel.filterCriteria.showOnlyFavorites = true
        viewModel.filterCriteria.minRating = 4
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "お気に入り + 4星以上")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
        XCTAssertFalse(viewModel.fileItems.contains { $0.url == url2 })
        XCTAssertFalse(viewModel.fileItems.contains { $0.url == url3 })
    }
    
    // MARK: - お気に入りとカラーラベルの組み合わせ
    
    func testCombination_FavoriteAndColor() {
        let url1 = URL(fileURLWithPath: "/fav_blue.jpg")
        let url2 = URL(fileURLWithPath: "/fav_red.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, colorLabel: "Blue", isFavorite: true)
        let item2 = FileItem(url: url2, isDirectory: false, colorLabel: "Red", isFavorite: true)
        
        viewModel.allFiles = [item1, item2]
        viewModel.appMode = .folders
        viewModel.filterCriteria.showOnlyFavorites = true
        viewModel.filterCriteria.colorLabel = "Blue"
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "お気に入り + Blue")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    // MARK: - お気に入りとフラグの組み合わせ
    
    func testCombination_FavoriteAndFlag() {
        let url1 = URL(fileURLWithPath: "/fav_pick.jpg")
        let url2 = URL(fileURLWithPath: "/fav_reject.jpg")
        let url3 = URL(fileURLWithPath: "/fav_none.jpg")
        
        let item1 = FileItem(url: url1, isDirectory: false, isFavorite: true, flagStatus: 1)
        let item2 = FileItem(url: url2, isDirectory: false, isFavorite: true, flagStatus: -1)
        let item3 = FileItem(url: url3, isDirectory: false, isFavorite: true, flagStatus: 0)
        
        viewModel.allFiles = [item1, item2, item3]
        viewModel.appMode = .folders
        viewModel.filterCriteria.showOnlyFavorites = true
        viewModel.filterCriteria.flagFilter = .pick
        viewModel.applyFilter()
        
        XCTAssertEqual(viewModel.fileItems.count, 1, "お気に入り + Pick")
        XCTAssertTrue(viewModel.fileItems.contains { $0.url == url1 })
    }
    
    // MARK: - CoreDataへの永続化
    
    func testCoreData_SaveFavorite() throws {
        let catalog = Catalog(context: context)
        catalog.id = UUID()
        catalog.name = "Test Catalog"
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.originalPath = "/test/favorite.jpg"
        item.isFavorite = true
        item.catalog = catalog
        
        try context.save()
        
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "originalPath == %@", "/test/favorite.jpg")
        let results = try context.fetch(request)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.isFavorite == true, "お気に入りが永続化される")
    }
    
    func testCoreData_SaveNotFavorite() throws {
        let catalog = Catalog(context: context)
        catalog.id = UUID()
        catalog.name = "Test Catalog"
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.originalPath = "/test/normal.jpg"
        item.isFavorite = false
        item.catalog = catalog
        
        try context.save()
        
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "originalPath == %@", "/test/normal.jpg")
        let results = try context.fetch(request)
        
        XCTAssertEqual(results.first?.isFavorite, false, "非お気に入りが永続化される")
    }
    
    func testCoreData_UpdateFavoriteStatus() throws {
        let catalog = Catalog(context: context)
        catalog.id = UUID()
        catalog.name = "Test Catalog"
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.originalPath = "/test/toggle.jpg"
        item.isFavorite = false
        item.catalog = catalog
        
        try context.save()
        
        // トグル: false -> true
        item.isFavorite = true
        try context.save()
        
        let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
        request.predicate = NSPredicate(format: "originalPath == %@", "/test/toggle.jpg")
        let results = try context.fetch(request)
        
        XCTAssertTrue(results.first?.isFavorite == true, "お気に入り状態が更新される")
    }
    
    // MARK: - フォルダモードでのお気に入り
    
    func testFolderMode_FavoriteHandling() {
        viewModel.appMode = .folders
        
        // フォルダモードではメタデータキャッシュを使用（実装による）
        let url = URL(fileURLWithPath: "/folder/test.jpg")
        let item = FileItem(url: url, isDirectory: false, isFavorite: true)
        
        XCTAssertEqual(item.isFavorite, true)
        XCTAssertEqual(viewModel.appMode, .folders)
    }
    
    // MARK: - カタログモードでのお気に入り
    
    func testCatalogMode_FavoriteInCoreData() throws {
        viewModel.appMode = .catalog
        
        let catalog = Catalog(context: context)
        catalog.id = UUID()
        catalog.name = "Favorite Test Catalog"
        
        let item = MediaItem(context: context)
        item.id = UUID()
        item.isFavorite = true
        item.catalog = catalog
        
        try context.save()
        
        XCTAssertTrue(item.isFavorite)
        XCTAssertEqual(viewModel.appMode, .catalog)
    }
    
    // MARK: - マルチセレクション時の状態表示
    
    func testMultiSelection_AllFavorites() {
        let item1 = FileItem(url: URL(fileURLWithPath: "/1.jpg"), isDirectory: false, isFavorite: true)
        let item2 = FileItem(url: URL(fileURLWithPath: "/2.jpg"), isDirectory: false, isFavorite: true)
        
        viewModel.selectedFiles = [item1, item2]
        
        let favorites = viewModel.selectedFiles.compactMap { $0.isFavorite }
        XCTAssertTrue(favorites.allSatisfy { $0 == true }, "全てお気に入り")
    }
    
    func testMultiSelection_MixedFavorites() {
        let item1 = FileItem(url: URL(fileURLWithPath: "/1.jpg"), isDirectory: false, isFavorite: true)
        let item2 = FileItem(url: URL(fileURLWithPath: "/2.jpg"), isDirectory: false, isFavorite: false)
        
        viewModel.selectedFiles = [item1, item2]
        
        let favorites = viewModel.selectedFiles.compactMap { $0.isFavorite }
        XCTAssertTrue(favorites.contains(true), "お気に入りを含む")
        XCTAssertTrue(favorites.contains(false), "非お気に入りも含む")
    }
    
    func testMultiSelection_NilFavorites() {
        let item1 = FileItem(url: URL(fileURLWithPath: "/1.jpg"), isDirectory: false, isFavorite: true)
        let item2 = FileItem(url: URL(fileURLWithPath: "/2.jpg"), isDirectory: false, isFavorite: nil)
        
        viewModel.selectedFiles = [item1, item2]
        
        let favTrue = viewModel.selectedFiles.filter { $0.isFavorite == true }
        let favNil = viewModel.selectedFiles.filter { $0.isFavorite == nil }
        
        XCTAssertEqual(favTrue.count, 1)
        XCTAssertEqual(favNil.count, 1)
    }
    
    // MARK: - 複数ファイルへの一括設定
    
    func testBulkSet_MarkMultipleAsFavorite() {
        var item1 = FileItem(url: URL(fileURLWithPath: "/1.jpg"), isDirectory: false)
        var item2 = FileItem(url: URL(fileURLWithPath: "/2.jpg"), isDirectory: false)
        
        // 一括でお気に入り設定
        item1 = FileItem(url: item1.url, isDirectory: false, uuid: item1.uuid, isFavorite: true)
        item2 = FileItem(url: item2.url, isDirectory: false, uuid: item2.uuid, isFavorite: true)
        
        XCTAssertEqual(item1.isFavorite, true)
        XCTAssertEqual(item2.isFavorite, true)
    }
    
    func testBulkSet_UnmarkMultipleAsFavorite() {
        var item1 = FileItem(url: URL(fileURLWithPath: "/1.jpg"), isDirectory: false, isFavorite: true)
        var item2 = FileItem(url: URL(fileURLWithPath: "/2.jpg"), isDirectory: false, isFavorite: true)
        
        // 一括で解除
        item1 = FileItem(url: item1.url, isDirectory: false, uuid: item1.uuid, isFavorite: false)
        item2 = FileItem(url: item2.url, isDirectory: false, uuid: item2.uuid, isFavorite: false)
        
        XCTAssertEqual(item1.isFavorite, false)
        XCTAssertEqual(item2.isFavorite, false)
    }
}
