import XCTest
@testable import SwiftViewerCore

/// ISO 抽出のテスト。
/// 背景: Pentax は EXIF の ISO タグにエンコード値（6=ISO100, 9=200, …）を格納し、
/// 旧 Nikon は "0 200" のような複数値を返す。ExifTool の print-conversion（`-ISO`、`#` なし）
/// を使い、さらに parseISO で複数値文字列/配列を頑健に扱う。
final class ISOExtractionTests: XCTestCase {

    private let reader = ExifReader.shared

    // MARK: - parseISO 単体テスト（ファイル非依存）

    func testParseISO_PlainInt() {
        XCTAssertEqual(reader.parseISO(100), 100)
        XCTAssertEqual(reader.parseISO(1600), 1600)
    }

    func testParseISO_PlainString() {
        XCTAssertEqual(reader.parseISO("200"), 200)
    }

    func testParseISO_Double() {
        XCTAssertEqual(reader.parseISO(400.0), 400)
    }

    /// 旧 Nikon の "0 200" は最後の正の整数（200）を採用する。
    func testParseISO_MultiValueString() {
        XCTAssertEqual(reader.parseISO("0 200"), 200)
        XCTAssertEqual(reader.parseISO("0 640"), 640)
    }

    /// 配列 [0, 200] でも 0 を拾わず 200 を返す。
    func testParseISO_Array() {
        XCTAssertEqual(reader.parseISO([0, 200]), 200)
        XCTAssertEqual(reader.parseISO([100]), 100)
    }

    /// 0 / 空 / nil は Unknown（nil）として扱う。
    func testParseISO_ZeroAndEmptyAreNil() {
        XCTAssertNil(reader.parseISO(0))
        XCTAssertNil(reader.parseISO("0"))
        XCTAssertNil(reader.parseISO("0 0"))
        XCTAssertNil(reader.parseISO(""))
        XCTAssertNil(reader.parseISO(nil))
    }

    // MARK: - 実ファイル統合テスト（サンプルが無ければ skip）

    private static let rawsRoot = "/Users/uniuyuni/Downloads/raws"

    /// Pentax: 実 ISO は 100。`-ISO#`（生値）だと 6 になってしまうのが本バグ。
    func testPentaxISO_RealValueIs100() throws {
        let path = "\(Self.rawsRoot)/pentax/k10d/RAW_PENTAX_K10D_SRGB.PEF"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Pentax sample not found at \(path)")
        }
        let meta = reader.readExifUsingExifTool(from: URL(fileURLWithPath: path))
        XCTAssertEqual(meta?.iso, 100, "Pentax K10D の実 ISO は 100（生エンコード値 6 ではない）")
    }

    /// 旧 Nikon D70: 実 ISO は 200（"0 200" の生値ではなく最後の正値）。
    func testOldNikonISO_RealValueIs200() throws {
        let path = "\(Self.rawsRoot)/nikon/d70/RAW_NIKON_D70.NEF"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Nikon sample not found at \(path)")
        }
        let meta = reader.readExifUsingExifTool(from: URL(fileURLWithPath: path))
        XCTAssertEqual(meta?.iso, 200, "Nikon D70 の実 ISO は 200")
    }

    /// 通常機種（スマホ DNG）は従来通り正しい ISO を返す（リグレッション防止）。
    func testNormalISO_Unchanged() throws {
        let path = "\(Self.rawsRoot)/phones/RAW_ONEPLUS_ONE-A0001.DNG"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Phone sample not found at \(path)")
        }
        let meta = reader.readExifUsingExifTool(from: URL(fileURLWithPath: path))
        XCTAssertEqual(meta?.iso, 100)
    }
}
