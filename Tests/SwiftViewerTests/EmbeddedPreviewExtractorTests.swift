import XCTest
@testable import SwiftViewerCore

/// 埋め込みプレビュー抽出のテスト。
/// 背景: 同一ファイルに複数の埋め込み画像があり、最初に見つかるものが最大とは限らない
/// （Nikon: PreviewImage 27KB vs JpgFromRaw 578KB）。また TIFF 系プレビュー
/// （PreviewTIFF/ThumbnailTIFF）はバイナリ走査では拾えない。バイトサイズ最大のタグを採用する。
final class EmbeddedPreviewExtractorTests: XCTestCase {

    private let extractor = EmbeddedPreviewExtractor.shared
    private static let rawsRoot = "/Users/uniuyuni/Downloads/raws"

    // MARK: - parseBinaryByteCount 単体テスト（ファイル非依存）

    func testParseBinaryByteCount() {
        XCTAssertEqual(extractor.parseBinaryByteCount("(Binary data 578350 bytes, use -b option to extract)"), 578350)
        XCTAssertEqual(extractor.parseBinaryByteCount("(Binary data 1732056 bytes, use -b to extract)"), 1732056)
        XCTAssertEqual(extractor.parseBinaryByteCount("(Binary data 0 bytes)"), 0)
        XCTAssertNil(extractor.parseBinaryByteCount("-"))
        XCTAssertNil(extractor.parseBinaryByteCount(""))
    }

    // MARK: - largestPreviewTag 統合テスト（サンプルが無ければ skip）

    /// Nikon D70: PreviewImage(27KB) より JpgFromRaw(578KB) が大きい。
    func testLargestPreviewTag_NikonPrefersJpgFromRaw() throws {
        let path = "\(Self.rawsRoot)/nikon/d70/RAW_NIKON_D70.NEF"
        try skipIfMissing(path)
        XCTAssertEqual(extractor.largestPreviewTag(url: URL(fileURLWithPath: path)), "JpgFromRaw")
    }

    /// Nokia DNG: PreviewImage/JpgFromRaw が無く、TIFF プレビューのみ（タグでしか取れない）。
    func testLargestPreviewTag_NokiaPrefersPreviewTIFF() throws {
        let path = "\(Self.rawsRoot)/phones/RAW_NOKIA_LUMIA_1020.DNG"
        try skipIfMissing(path)
        XCTAssertEqual(extractor.largestPreviewTag(url: URL(fileURLWithPath: path)), "PreviewTIFF")
    }

    /// Kodak P880: 大プレビューは OtherImage に入っている。
    func testLargestPreviewTag_KodakPrefersOtherImage() throws {
        let path = "\(Self.rawsRoot)/kodak/p880/RAW_KODAK_P880.KDC"
        try skipIfMissing(path)
        XCTAssertEqual(extractor.largestPreviewTag(url: URL(fileURLWithPath: path)), "OtherImage")
    }

    // MARK: - extractPreview 統合テスト

    /// 従来 binary-scan では取れなかった TIFF プレビューが取得できる。
    func testExtractPreview_NokiaDNG_ReturnsImage() throws {
        let path = "\(Self.rawsRoot)/phones/RAW_NOKIA_LUMIA_1020.DNG"
        try skipIfMissing(path)
        let image = extractor.extractPreview(from: URL(fileURLWithPath: path))
        XCTAssertNotNil(image, "Nokia DNG の PreviewTIFF からプレビューが得られるはず")
        if let image = image {
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        }
    }

    private func skipIfMissing(_ path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Sample not found at \(path)")
        }
    }
}
