import XCTest
@testable import SwiftViewerCore

final class DocumentLogConfigurationTests: XCTestCase {
    func testDocumentLogsAreDisabledWhenEnvironmentVariableIsMissing() {
        XCTAssertFalse(DocumentLogConfiguration.isEnabled(environment: [:]))
    }

    func testDocumentLogsAreEnabledOnlyWhenEnvironmentVariableIsOne() {
        XCTAssertTrue(DocumentLogConfiguration.isEnabled(environment: [
            DocumentLogConfiguration.environmentVariableName: "1"
        ]))
        XCTAssertFalse(DocumentLogConfiguration.isEnabled(environment: [
            DocumentLogConfiguration.environmentVariableName: "true"
        ]))
        XCTAssertFalse(DocumentLogConfiguration.isEnabled(environment: [
            DocumentLogConfiguration.environmentVariableName: "0"
        ]))
    }
}
