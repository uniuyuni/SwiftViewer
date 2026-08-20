import Foundation

class Logger {
    static let shared = Logger()
    
    private let logFileURL: URL?
    private let queue = DispatchQueue(label: "com.swiftviewer.logger", qos: .utility)
    
    private init() {
        guard DocumentLogConfiguration.isEnabled,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            logFileURL = nil
            return
        }

        let url = documents.appendingPathComponent("SwiftViewer_Debug.log")
        logFileURL = url

        if !FileManager.default.fileExists(atPath: url.path) {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    func log(_ message: String) {
        queue.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            let logMessage = "[\(timestamp)] \(message)\n"
            
            print(logMessage) // Also print to stdout
            
            if let logFileURL = self.logFileURL,
               let data = logMessage.data(using: .utf8) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            }
        }
    }
    
    func clear() {
        queue.async {
            guard let logFileURL = self.logFileURL else { return }
            try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }
}
