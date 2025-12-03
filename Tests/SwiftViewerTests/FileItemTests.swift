import XCTest
@testable import SwiftViewerCore

/// FileItem構造体の包括的なテスト
/// FileItemはSwiftViewerの中核データモデルで、ファイルとディレクトリを統一的に表現します
final class FileItemTests: XCTestCase {
    
    // MARK: - 基本的なプロパティの初期化
    
    func testBasicInitialization() {
        let url = URL(fileURLWithPath: "/Users/test/image.jpg")
        let item = FileItem(url: url, isDirectory: false)
        
        XCTAssertEqual(item.url, url)
        XCTAssertFalse(item.isDirectory)
        XCTAssertEqual(item.name, "image.jpg")
        XCTAssertTrue(item.isAvailable)
        XCTAssertFalse(item.isConflict)
        XCTAssertNil(item.uuid)
        XCTAssertNil(item.colorLabel)
        XCTAssertNil(item.isFavorite)
        XCTAssertNil(item.flagStatus)
    }
    
    func testDirectoryInitialization() {
        let url = URL(fileURLWithPath: "/Users/test/Photos")
        let item = FileItem(url: url, isDirectory: true, fileCount: 42)
        
        XCTAssertTrue(item.isDirectory)
        XCTAssertEqual(item.fileCount, 42)
        XCTAssertEqual(item.name, "Photos")
    }
    
    // MARK: - UUID vs URLパスベースのID生成
    
    func testIDGeneration_WithUUID() {
        let url = URL(fileURLWithPath: "/test.jpg")
        let uuid = UUID()
        let item = FileItem(url: url, isDirectory: false, uuid: uuid)
        
        XCTAssertEqual(item.id, uuid.uuidString)
    }
    
    func testIDGeneration_WithoutUUID() {
        let url = URL(fileURLWithPath: "/Users/test/file.jpg")
        let item = FileItem(url: url, isDirectory: false)
        
        XCTAssertEqual(item.id, url.path)
    }
    
    func testIDGeneration_PreferUUIDOverPath() {
        let url = URL(fileURLWithPath: "/test.jpg")
        let uuid = UUID()
        let item = FileItem(url: url, isDirectory: false, uuid: uuid)
        
        // UUIDが存在する場合、UUIDベースのIDを使用
        XCTAssertEqual(item.id, uuid.uuidString)
        XCTAssertNotEqual(item.id, url.path)
    }
    
    // MARK: - Equatable実装
    
    func testEquality_SameID() {
        let url = URL(fileURLWithPath: "/test.jpg")
        let uuid = UUID()
        
        let item1 = FileItem(url: url, isDirectory: false, uuid: uuid)
        let item2 = FileItem(url: url, isDirectory: false, uuid: uuid)
        
        XCTAssertEqual(item1, item2, "同じIDを持つアイテムは等しい")
    }
    
    func testEquality_DifferentUUID() {
        let url = URL(fileURLWithPath: "/test.jpg")
        
        let item1 = FileItem(url: url, isDirectory: false, uuid: UUID())
        let item2 = FileItem(url: url, isDirectory: false, uuid: UUID())
        
        XCTAssertNotEqual(item1, item2, "異なるUUIDを持つアイテムは異なる")
    }
    
    func testEquality_SamePath_NoUUID() {
        let url = URL(fileURLWithPath: "/test.jpg")
        
        let item1 = FileItem(url: url, isDirectory: false)
        let item2 = FileItem(url: url, isDirectory: false)
        
        XCTAssertEqual(item1, item2, "UUIDなしの場合、同じパスなら等しい")
    }
    
    func testEquality_DifferentPath_NoUUID() {
        let item1 = FileItem(url: URL(fileURLWithPath: "/test1.jpg"), isDirectory: false)
        let item2 = FileItem(url: URL(fileURLWithPath: "/test2.jpg"), isDirectory: false)
        
        XCTAssertNotEqual(item1, item2, "異なるパスのアイテムは異なる")
    }
    
    // MARK: - Hashable実装
    
    func testHashable_SetMembership() {
        let url = URL(fileURLWithPath: "/test.jpg")
        let uuid = UUID()
        
        let item1 = FileItem(url: url, isDirectory: false, uuid: uuid)
        let item2 = FileItem(url: url, isDirectory: false, uuid: uuid)
        
        var set = Set<FileItem>()
        set.insert(item1)
        set.insert(item2)
        
        XCTAssertEqual(set.count, 1, "同じIDのアイテムはSetで1つとしてカウント")
    }
    
    func testHashable_DictionaryKey() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        
        let item1 = FileItem(url: URL(fileURLWithPath: "/1.jpg"), isDirectory: false, uuid: uuid1)
        let item2 = FileItem(url: URL(fileURLWithPath: "/2.jpg"), isDirectory: false, uuid: uuid2)
        
        var dict: [FileItem: String] = [:]
        dict[item1] = "First"
        dict[item2] = "Second"
        
        XCTAssertEqual(dict[item1], "First")
        XCTAssertEqual(dict[item2], "Second")
        XCTAssertEqual(dict.count, 2)
    }
    
    // MARK: - colorLabelの7色
    
    func testColorLabel_Red() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, colorLabel: "Red")
        XCTAssertEqual(item.colorLabel, "Red")
    }
    
    func testColorLabel_AllColors() {
        let colors = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"]
        
        for color in colors {
            let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, colorLabel: color)
            XCTAssertEqual(item.colorLabel, color, "\(color)ラベルが正しく設定される")
        }
    }
    
    func testColorLabel_Nil() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, colorLabel: nil)
        XCTAssertNil(item.colorLabel, "カラーラベルなしの状態")
    }
    
    // MARK: - isFavorite
    
    func testFavorite_True() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, isFavorite: true)
        XCTAssertTrue(item.isFavorite == true)
    }
    
    func testFavorite_False() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, isFavorite: false)
        XCTAssertTrue(item.isFavorite == false)
    }
    
    func testFavorite_Nil() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, isFavorite: nil)
        XCTAssertNil(item.isFavorite)
    }
    
    // MARK: - flagStatus（-1/0/1）
    
    func testFlagStatus_Pick() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, flagStatus: 1)
        XCTAssertEqual(item.flagStatus, 1, "Pickフラグ")
    }
    
    func testFlagStatus_Reject() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, flagStatus: -1)
        XCTAssertEqual(item.flagStatus, -1, "Rejectフラグ")
    }
    
    func testFlagStatus_None() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, flagStatus: 0)
        XCTAssertEqual(item.flagStatus, 0, "フラグなし")
    }
    
    func testFlagStatus_Nil() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, flagStatus: nil)
        XCTAssertNil(item.flagStatus)
    }
    
    // MARK: - orientation（1-8の値）
    
    func testOrientation_AllValues() {
        for orientation in 1...8 {
            let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, orientation: orientation)
            XCTAssertEqual(item.orientation, orientation, "Orientation \(orientation)")
        }
    }
    
    func testOrientation_Nil() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, orientation: nil)
        XCTAssertNil(item.orientation)
    }
    
    // MARK: - ディレクトリ vs ファイル
    
    func testIsDirectory_File() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false)
        XCTAssertFalse(item.isDirectory)
        XCTAssertNil(item.fileCount)
    }
    
    func testIsDirectory_Folder() {
        let item = FileItem(url: URL(fileURLWithPath: "/Photos"), isDirectory: true, fileCount: 100)
        XCTAssertTrue(item.isDirectory)
        XCTAssertEqual(item.fileCount, 100)
    }
    
    // MARK: - isAvailable
    
    func testIsAvailable_True() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, isAvailable: true)
        XCTAssertTrue(item.isAvailable)
    }
    
    func testIsAvailable_False() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, isAvailable: false)
        XCTAssertFalse(item.isAvailable, "利用不可（仮想フォルダ等）")
    }
    
    // MARK: - isConflict
    
    func testIsConflict_Default() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false)
        XCTAssertFalse(item.isConflict, "デフォルトは競合なし")
    }
    
    func testIsConflict_True() {
        var item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false)
        item.isConflict = true
        XCTAssertTrue(item.isConflict)
    }
    
    // MARK: - ファイルサイズの境界値
    
    func testFileSize_Zero() {
        let item = FileItem(url: URL(fileURLWithPath: "/empty.txt"), isDirectory: false, fileSize: 0)
        XCTAssertEqual(item.fileSize, 0)
    }
    
    func testFileSize_Large() {
        let largeSize: Int64 = 10_000_000_000 // 10GB
        let item = FileItem(url: URL(fileURLWithPath: "/large.dat"), isDirectory: false, fileSize: largeSize)
        XCTAssertEqual(item.fileSize, largeSize)
    }
    
    func testFileSize_Nil() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, fileSize: nil)
        XCTAssertNil(item.fileSize)
    }
    
    // MARK: - 日付プロパティ
    
    func testDates_Nil() {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false)
        XCTAssertNil(item.creationDate)
        XCTAssertNil(item.modificationDate)
    }
    
    func testDates_Past() {
        let pastDate = Date(timeIntervalSince1970: 0) // 1970-01-01
        let item = FileItem(
            url: URL(fileURLWithPath: "/old.jpg"),
            isDirectory: false,
            creationDate: pastDate,
            modificationDate: pastDate
        )
        XCTAssertEqual(item.creationDate, pastDate)
        XCTAssertEqual(item.modificationDate, pastDate)
    }
    
    func testDates_Future() {
        let futureDate = Date(timeIntervalSinceNow: 86400 * 365) // 1年後
        let item = FileItem(
            url: URL(fileURLWithPath: "/future.jpg"),
            isDirectory: false,
            creationDate: futureDate,
            modificationDate: futureDate
        )
        XCTAssertEqual(item.creationDate, futureDate)
        XCTAssertEqual(item.modificationDate, futureDate)
    }
    
    func testDates_DifferentCreationAndModification() {
        let created = Date(timeIntervalSince1970: 1000)
        let modified = Date(timeIntervalSince1970: 2000)
        let item = FileItem(
            url: URL(fileURLWithPath: "/test.jpg"),
            isDirectory: false,
            creationDate: created,
            modificationDate: modified
        )
        XCTAssertEqual(item.creationDate, created)
        XCTAssertEqual(item.modificationDate, modified)
        XCTAssertNotEqual(item.creationDate, item.modificationDate)
    }
    
    // MARK: - URLの特殊文字処理
    
    func testURL_SpecialCharacters() {
        let specialNames = [
            "photo with spaces.jpg",
            "日本語ファイル.jpg",
            "emoji🎉.jpg",
            "special#$%chars.jpg",
            "parens(1).jpg"
        ]
        
        for name in specialNames {
            let url = URL(fileURLWithPath: "/\(name)")
            let item = FileItem(url: url, isDirectory: false)
            XCTAssertEqual(item.name, name, "\(name)が正しく処理される")
        }
    }
    
    func testURL_LongPath() {
        let longComponent = String(repeating: "a", count: 200)
        let url = URL(fileURLWithPath: "/\(longComponent).jpg")
        let item = FileItem(url: url, isDirectory: false)
        XCTAssertEqual(item.name, "\(longComponent).jpg")
    }
    
    // MARK: - 複数プロパティの組み合わせ
    
    func testCompleteInitialization() {
        let url = URL(fileURLWithPath: "/complete.jpg")
        let uuid = UUID()
        let created = Date(timeIntervalSince1970: 1000)
        let modified = Date(timeIntervalSince1970: 2000)
        
        let item = FileItem(
            url: url,
            isDirectory: false,
            isAvailable: true,
            uuid: uuid,
            colorLabel: "Blue",
            isFavorite: true,
            flagStatus: 1,
            fileCount: nil,
            creationDate: created,
            modificationDate: modified,
            fileSize: 1024000,
            orientation: 6
        )
        
        XCTAssertEqual(item.url, url)
        XCTAssertFalse(item.isDirectory)
        XCTAssertEqual(item.uuid, uuid)
        XCTAssertEqual(item.colorLabel, "Blue")
        XCTAssertEqual(item.isFavorite, true)
        XCTAssertEqual(item.flagStatus, 1)
        XCTAssertEqual(item.creationDate, created)
        XCTAssertEqual(item.modificationDate, modified)
        XCTAssertEqual(item.fileSize, 1024000)
        XCTAssertEqual(item.orientation, 6)
    }
    
    // MARK: - Sendable準拠の検証
    
    func testSendable_ConcurrentAccess() async {
        let item = FileItem(url: URL(fileURLWithPath: "/test.jpg"), isDirectory: false, uuid: UUID())
        
        // 並行アクセスでもコンパイルエラーがないことを確認
        async let task1 = checkItem(item)
        async let task2 = checkItem(item)
        
        let result1 = await task1
        let result2 = await task2
        
        XCTAssertTrue(result1)
        XCTAssertTrue(result2)
    }
    
    private func checkItem(_ item: FileItem) async -> Bool {
        return item.url.path.count > 0
    }
}
