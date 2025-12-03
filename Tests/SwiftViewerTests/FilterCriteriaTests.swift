import XCTest
@testable import SwiftViewerCore

/// FilterCriteria構造体とフィルタロジックの包括的なテスト
/// FilterCriteriaは高度なフィルタリング機能を制御する中核データモデルです
final class FilterCriteriaTests: XCTestCase {
    
    // MARK: - デフォルト値の検証
    
    func testDefaultValues() {
        let criteria = FilterCriteria()
        
        XCTAssertEqual(criteria.minRating, 0)
        XCTAssertNil(criteria.colorLabel)
        XCTAssertTrue(criteria.showImages)
        XCTAssertTrue(criteria.showVideos)
        XCTAssertEqual(criteria.searchText, "")
        XCTAssertFalse(criteria.showOnlyFavorites)
        XCTAssertEqual(criteria.flagFilter, .all)
        
        // メタデータフィルターは空
        XCTAssertTrue(criteria.selectedMakers.isEmpty)
        XCTAssertTrue(criteria.selectedCameras.isEmpty)
        XCTAssertTrue(criteria.selectedLenses.isEmpty)
        XCTAssertTrue(criteria.selectedISOs.isEmpty)
        XCTAssertTrue(criteria.selectedDates.isEmpty)
        XCTAssertTrue(criteria.selectedFileTypes.isEmpty)
        XCTAssertTrue(criteria.selectedShutterSpeeds.isEmpty)
        XCTAssertTrue(criteria.selectedApertures.isEmpty)
        XCTAssertTrue(criteria.selectedFocalLengths.isEmpty)
        
        // デフォルト表示列
        XCTAssertEqual(criteria.visibleColumns, [.date, .maker, .camera, .lens, .iso])
    }
    
    // MARK: - minRating（0-5の各値）
    
    func testMinRating_AllValues() {
        for rating in 0...5 {
            var criteria = FilterCriteria()
            criteria.minRating = rating
            XCTAssertEqual(criteria.minRating, rating, "レーティング\(rating)が正しく設定される")
        }
    }
    
    func testMinRating_Filtering() {
        var criteria = FilterCriteria()
        criteria.minRating = 3
        XCTAssertEqual(criteria.minRating, 3)
        XCTAssertTrue(criteria.isActive, "minRatingが0以上の場合、フィルタがアクティブ")
    }
    
    // MARK: - colorLabelフィルタ
    
    func testColorLabel_Individual() {
        let colors = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"]
        
        for color in colors {
            var criteria = FilterCriteria()
            criteria.colorLabel = color
            XCTAssertEqual(criteria.colorLabel, color, "\(color)フィルタが設定される")
            XCTAssertTrue(criteria.isActive)
        }
    }
    
    func testColorLabel_Nil() {
        var criteria = FilterCriteria()
        criteria.colorLabel = nil
        XCTAssertNil(criteria.colorLabel)
    }
    
    // MARK: - showImages/showVideosトグル
    
    func testShowImages_False() {
        var criteria = FilterCriteria()
        criteria.showImages = false
        XCTAssertFalse(criteria.showImages)
        XCTAssertTrue(criteria.isActive, "画像非表示でフィルタアクティブ")
    }
    
    func testShowVideos_False() {
        var criteria = FilterCriteria()
        criteria.showVideos = false
        XCTAssertFalse(criteria.showVideos)
        XCTAssertTrue(criteria.isActive, "動画非表示でフィルタアクティブ")
    }
    
    func testShowBoth_False() {
        var criteria = FilterCriteria()
        criteria.showImages = false
        criteria.showVideos = false
        XCTAssertFalse(criteria.showImages)
        XCTAssertFalse(criteria.showVideos)
    }
    
    // MARK: - searchText
    
    func testSearchText_Empty() {
        var criteria = FilterCriteria()
        criteria.searchText = ""
        XCTAssertEqual(criteria.searchText, "")
        XCTAssertFalse(criteria.isActive, "空のテキストはフィルタ非アクティブ")
    }
    
    func testSearchText_NotEmpty() {
        var criteria = FilterCriteria()
        criteria.searchText = "vacation"
        XCTAssertEqual(criteria.searchText, "vacation")  
        XCTAssertTrue(criteria.isActive)
    }
    
    func testSearchText_SpecialCharacters() {
        var criteria = FilterCriteria()
        criteria.searchText = "日本語 🎉 [test]"
        XCTAssertEqual(criteria.searchText, "日本語 🎉 [test]")
    }
    
    // MARK: - showOnlyFavorites
    
    func testShowOnlyFavorites_True() {
        var criteria = FilterCriteria()
        criteria.showOnlyFavorites = true
        XCTAssertTrue(criteria.showOnlyFavorites)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testShowOnlyFavorites_False() {
        var criteria = FilterCriteria()
        criteria.showOnlyFavorites = false
        XCTAssertFalse(criteria.showOnlyFavorites)
    }
    
    // MARK: - FlagFilter列挙型
    
    func testFlagFilter_All() {
        var criteria = FilterCriteria()
        criteria.flagFilter = .all
        XCTAssertEqual(criteria.flagFilter, .all)
        XCTAssertFalse(criteria.isActive, "allはフィルタ非アクティブ")
    }
    
    func testFlagFilter_Flagged() {
        var criteria = FilterCriteria()
        criteria.flagFilter = .flagged
        XCTAssertEqual(criteria.flagFilter, .flagged)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testFlagFilter_Unflagged() {
        var criteria = FilterCriteria()
        criteria.flagFilter = .unflagged
        XCTAssertEqual(criteria.flagFilter, .unflagged)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testFlagFilter_Pick() {
        var criteria = FilterCriteria()
        criteria.flagFilter = .pick
        XCTAssertEqual(criteria.flagFilter, .pick)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testFlagFilter_Reject() {
        var criteria = FilterCriteria()
        criteria.flagFilter = .reject
        XCTAssertEqual(criteria.flagFilter, .reject)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testFlagFilter_AllCases() {
        let allCases = FilterCriteria.FlagFilter.allCases
        XCTAssertEqual(allCases.count, 5)
        XCTAssertTrue(allCases.contains(.all))
        XCTAssertTrue(allCases.contains(.flagged))
        XCTAssertTrue(allCases.contains(.unflagged))
        XCTAssertTrue(allCases.contains(.pick))
        XCTAssertTrue(allCases.contains(.reject))
    }
    
    // MARK: - selectedMakers
    
    func testSelectedMakers_Single() {
        var criteria = FilterCriteria()
        criteria.selectedMakers = ["Canon"]
        XCTAssertEqual(criteria.selectedMakers.count, 1)
        XCTAssertTrue(criteria.selectedMakers.contains("Canon"))
        XCTAssertTrue(criteria.isActive)
    }
    
    func testSelectedMakers_Multiple() {
        var criteria = FilterCriteria()
        criteria.selectedMakers = ["Canon", "Nikon", "Sony"]
        XCTAssertEqual(criteria.selectedMakers.count, 3)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testSelectedMakers_Empty() {
        var criteria = FilterCriteria()
        criteria.selectedMakers = []
        XCTAssertTrue(criteria.selectedMakers.isEmpty)
    }
    
    // MARK: - selectedCameras
    
    func testSelectedCameras_Single() {
        var criteria = FilterCriteria()
        criteria.selectedCameras = ["EOS R5"]
        XCTAssertEqual(criteria.selectedCameras.count, 1)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testSelectedCameras_Multiple() {
        var criteria = FilterCriteria()
        criteria.selectedCameras = ["EOS R5", "D850", "A7R IV"]
        XCTAssertEqual(criteria.selectedCameras.count, 3)
    }
    
    // MARK: - selectedLenses
    
    func testSelectedLenses_Single() {
        var criteria = FilterCriteria()
        criteria.selectedLenses = ["RF 24-70mm f/2.8L"]
        XCTAssertEqual(criteria.selectedLenses.count, 1)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testSelectedLenses_Multiple() {
        var criteria = FilterCriteria()
        criteria.selectedLenses = ["RF 24-70mm f/2.8L", "AF-S 70-200mm f/2.8E"]
        XCTAssertEqual(criteria.selectedLenses.count, 2)
    }
    
    // MARK: - selectedISOs
    
    func testSelectedISOs_Single() {
        var criteria = FilterCriteria()
        criteria.selectedISOs = ["100"]
        XCTAssertEqual(criteria.selectedISOs.count, 1)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testSelectedISOs_Multiple() {
        var criteria = FilterCriteria()
        criteria.selectedISOs = ["100", "400", "1600"]
        XCTAssertEqual(criteria.selectedISOs.count, 3)
    }
    
    // MARK: - selectedDates
    
    func testSelectedDates_Single() {
        var criteria = FilterCriteria()
        criteria.selectedDates = ["2024-01-15"]
        XCTAssertEqual(criteria.selectedDates.count, 1)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testSelectedDates_Multiple() {
        var criteria = FilterCriteria()
        criteria.selectedDates = ["2024-01-15", "2024-02-20", "2024-03-10"]
        XCTAssertEqual(criteria.selectedDates.count, 3)
    }
    
    // MARK: - selectedFileTypes
    
    func testSelectedFileTypes_JPG() {
        var criteria = FilterCriteria()
        criteria.selectedFileTypes = ["JPG"]
        XCTAssertTrue(criteria.selectedFileTypes.contains("JPG"))
        XCTAssertTrue(criteria.isActive)
    }
    
    func testSelectedFileTypes_RAW() {
        var criteria = FilterCriteria()
        criteria.selectedFileTypes = ["CR2", "NEF", "ARW"]
        XCTAssertEqual(criteria.selectedFileTypes.count, 3)
    }
    
    func testSelectedFileTypes_Mixed() {
        var criteria = FilterCriteria()
        criteria.selectedFileTypes = ["JPG", "CR2", "PNG", "HEIC"]
        XCTAssertEqual(criteria.selectedFileTypes.count, 4)
    }
    
    // MARK: - selectedShutterSpeeds
    
    func testSelectedShutterSpeeds_Single() {
        var criteria = FilterCriteria()
        criteria.selectedShutterSpeeds = ["1/1000"]
        XCTAssertEqual(criteria.selectedShutterSpeeds.count, 1)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testSelectedShutterSpeeds_Multiple() {
        var criteria = FilterCriteria()
        criteria.selectedShutterSpeeds = ["1/1000", "1/500", "1/250"]
        XCTAssertEqual(criteria.selectedShutterSpeeds.count, 3)
    }
    
    // MARK: - selectedApertures
    
    func testSelectedApertures_Single() {
        var criteria = FilterCriteria()
        criteria.selectedApertures = ["f/2.8"]
        XCTAssertEqual(criteria.selectedApertures.count, 1)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testSelectedApertures_Multiple() {
        var criteria = FilterCriteria()
        criteria.selectedApertures = ["f/2.8", "f/4", "f/5.6"]
        XCTAssertEqual(criteria.selectedApertures.count, 3)
    }
    
    // MARK: - selectedFocalLengths
    
    func testSelectedFocalLengths_Single() {
        var criteria = FilterCriteria()
        criteria.selectedFocalLengths = ["85mm"]
        XCTAssertEqual(criteria.selectedFocalLengths.count, 1)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testSelectedFocalLengths_Multiple() {
        var criteria = FilterCriteria()
        criteria.selectedFocalLengths = ["24mm", "50mm", "85mm", "135mm"]
        XCTAssertEqual(criteria.selectedFocalLengths.count, 4)
    }
    
    // MARK: - visibleColumns
    
    func testVisibleColumns_Default() {
        let criteria = FilterCriteria()
        XCTAssertEqual(criteria.visibleColumns.count, 5)
        XCTAssertTrue(criteria.visibleColumns.contains(.date))
        XCTAssertTrue(criteria.visibleColumns.contains(.maker))
        XCTAssertTrue(criteria.visibleColumns.contains(.camera))
        XCTAssertTrue(criteria.visibleColumns.contains(.lens))
        XCTAssertTrue(criteria.visibleColumns.contains(.iso))
    }
    
    func testVisibleColumns_Custom() {
        var criteria = FilterCriteria()
        criteria.visibleColumns = [.fileType, .shutterSpeed, .aperture]
        XCTAssertEqual(criteria.visibleColumns.count, 3)
        XCTAssertTrue(criteria.visibleColumns.contains(.fileType))
        XCTAssertTrue(criteria.visibleColumns.contains(.shutterSpeed))
        XCTAssertTrue(criteria.visibleColumns.contains(.aperture))
    }
    
    func testVisibleColumns_AllTypes() {
        var criteria = FilterCriteria()
        criteria.visibleColumns = FilterCriteria.MetadataType.allCases
        XCTAssertEqual(criteria.visibleColumns.count, 9)
    }
    
    func testMetadataType_AllCases() {
        let allTypes = FilterCriteria.MetadataType.allCases
        XCTAssertEqual(allTypes.count, 9)
        XCTAssertTrue(allTypes.contains(.date))
        XCTAssertTrue(allTypes.contains(.fileType))
        XCTAssertTrue(allTypes.contains(.maker))
        XCTAssertTrue(allTypes.contains(.camera))
        XCTAssertTrue(allTypes.contains(.lens))
        XCTAssertTrue(allTypes.contains(.iso))
        XCTAssertTrue(allTypes.contains(.shutterSpeed))
        XCTAssertTrue(allTypes.contains(.aperture))
        XCTAssertTrue(allTypes.contains(.focalLength))
    }
    
    // MARK: - isActiveプロパティ
    
    func testIsActive_DefaultFalse() {
        let criteria = FilterCriteria()
        XCTAssertFalse(criteria.isActive, "デフォルト設定ではフィルタ非アクティブ")
    }
    
    func testIsActive_MinRating() {
        var criteria = FilterCriteria()
        criteria.minRating = 1
        XCTAssertTrue(criteria.isActive)
    }
    
    func testIsActive_ColorLabel() {
        var criteria = FilterCriteria()
        criteria.colorLabel = "Blue"
        XCTAssertTrue(criteria.isActive)
    }
    
    func testIsActive_ShowImages() {
        var criteria = FilterCriteria()
        criteria.showImages = false
        XCTAssertTrue(criteria.isActive)
    }
    
    func testIsActive_ShowVideos() {
        var criteria = FilterCriteria()
        criteria.showVideos = false
        XCTAssertTrue(criteria.isActive)
    }
    
    func testIsActive_SearchText() {
        var criteria = FilterCriteria()
        criteria.searchText = "test"
        XCTAssertTrue(criteria.isActive)
    }
    
    func testIsActive_Favorites() {
        var criteria = FilterCriteria()
        criteria.showOnlyFavorites = true
        XCTAssertTrue(criteria.isActive)
    }
    
    func testIsActive_FlagFilter() {
        var criteria = FilterCriteria()
        criteria.flagFilter = .pick
        XCTAssertTrue(criteria.isActive)
    }
    
    func testIsActive_MetadataFilter() {
        var criteria = FilterCriteria()
        criteria.selectedMakers = ["Canon"]
        XCTAssertTrue(criteria.isActive)
    }
    
    // MARK: - Codable
    
    func testCodable_Encoding() throws {
        var criteria = FilterCriteria()
        criteria.minRating = 4
        criteria.colorLabel = "Green"
        criteria.selectedMakers = ["Canon", "Nikon"]
        criteria.flagFilter = .pick
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)
        XCTAssertFalse(data.isEmpty)
    }
    
    func testCodable_Decoding() throws {
        var original = FilterCriteria()
        original.minRating = 4
        original.colorLabel = "Green"
        original.selectedMakers = ["Canon", "Nikon"]
        original.flagFilter = .pick
        original.showOnlyFavorites = true
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilterCriteria.self, from: data)
        
        XCTAssertEqual(decoded.minRating, 4)
        XCTAssertEqual(decoded.colorLabel, "Green")
        XCTAssertEqual(decoded.selectedMakers, ["Canon", "Nikon"])
        XCTAssertEqual(decoded.flagFilter, .pick)
        XCTAssertTrue(decoded.showOnlyFavorites)
    }
    
    func testCodable_RoundTrip() throws {
        var original = FilterCriteria()
        original.minRating = 3
        original.selectedCameras = ["EOS R5", "D850"]
        original.selectedISOs = ["100", "400"]
        original.visibleColumns = [.maker, .camera, .iso]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilterCriteria.self, from: data)
        
        XCTAssertEqual(decoded.minRating, original.minRating)
        XCTAssertEqual(decoded.selectedCameras, original.selectedCameras)
        XCTAssertEqual(decoded.selectedISOs, original.selectedISOs)
        XCTAssertEqual(decoded.visibleColumns, original.visibleColumns)
    }
    
    // MARK: - 複数フィルタの組み合わせ
    
    func testCombination_RatingAndColor() {
        var criteria = FilterCriteria()
        criteria.minRating = 4
        criteria.colorLabel = "Blue"
        
        XCTAssertEqual(criteria.minRating, 4)
        XCTAssertEqual(criteria.colorLabel, "Blue")
        XCTAssertTrue(criteria.isActive)
    }
    
    func testCombination_MakerAndCamera() {
        var criteria = FilterCriteria()
        criteria.selectedMakers = ["Canon"]
        criteria.selectedCameras = ["EOS R5", "EOS R6"]
        
        XCTAssertEqual(criteria.selectedMakers.count, 1)
        XCTAssertEqual(criteria.selectedCameras.count, 2)
        XCTAssertTrue(criteria.isActive)
    }
    
    func testCombination_ThreeFilters() {
        var criteria = FilterCriteria()
        criteria.selectedMakers = ["Canon"]
        criteria.selectedCameras = ["EOS R5"]
        criteria.selectedLenses = ["RF 24-70mm f/2.8L"]
        
        XCTAssertTrue(criteria.isActive)
        XCTAssertEqual(criteria.selectedMakers.count, 1)
        XCTAssertEqual(criteria.selectedCameras.count, 1)
        XCTAssertEqual(criteria.selectedLenses.count, 1)
    }
    
    func testCombination_AllMetadataFilters() {
        var criteria = FilterCriteria()
        criteria.selectedMakers = ["Canon"]
        criteria.selectedCameras = ["EOS R5"]
        criteria.selectedLenses = ["RF 24-70mm"]
        criteria.selectedISOs = ["100"]
        criteria.selectedDates = ["2024-01-15"]
        criteria.selectedFileTypes = ["CR2"]
        criteria.selectedShutterSpeeds = ["1/1000"]
        criteria.selectedApertures = ["f/2.8"]
        criteria.selectedFocalLengths = ["70mm"]
        
        XCTAssertTrue(criteria.isActive)
        XCTAssertFalse(criteria.selectedMakers.isEmpty)
        XCTAssertFalse(criteria.selectedCameras.isEmpty)
        XCTAssertFalse(criteria.selectedLenses.isEmpty)
        XCTAssertFalse(criteria.selectedISOs.isEmpty)
        XCTAssertFalse(criteria.selectedDates.isEmpty)
        XCTAssertFalse(criteria.selectedFileTypes.isEmpty)
        XCTAssertFalse(criteria.selectedShutterSpeeds.isEmpty)
        XCTAssertFalse(criteria.selectedApertures.isEmpty)
        XCTAssertFalse(criteria.selectedFocalLengths.isEmpty)
    }
    
    func testCombination_FlagAndFavorite() {
        var criteria = FilterCriteria()
        criteria.flagFilter = .pick
        criteria.showOnlyFavorites = true
        
        XCTAssertEqual(criteria.flagFilter, .pick)
        XCTAssertTrue(criteria.showOnlyFavorites)
        XCTAssertTrue(criteria.isActive)
    }
    
    // MARK: - フィルタのリセット
    
    func testReset_ToDefaults() {
        var criteria = FilterCriteria()
        criteria.minRating = 5
        criteria.colorLabel = "Red"
        criteria.selectedMakers = ["Canon"]
        criteria.showOnlyFavorites = true
        
        // リセット（新しいインスタンス作成）
        criteria = FilterCriteria()
        
        XCTAssertEqual(criteria.minRating, 0)
        XCTAssertNil(criteria.colorLabel)
        XCTAssertTrue(criteria.selectedMakers.isEmpty)
        XCTAssertFalse(criteria.showOnlyFavorites)
        XCTAssertFalse(criteria.isActive)
    }
}
