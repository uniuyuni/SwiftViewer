import Foundation

enum DocumentLogConfiguration {
    static let environmentVariableName = "SWIFTVIEWER_ENABLE_DOCUMENT_LOGS"

    static var isEnabled: Bool {
        isEnabled(environment: ProcessInfo.processInfo.environment)
    }

    static func isEnabled(environment: [String: String]) -> Bool {
        environment[environmentVariableName] == "1"
    }
}
