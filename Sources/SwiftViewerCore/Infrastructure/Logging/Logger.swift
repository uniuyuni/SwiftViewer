import Foundation

class Logger {
    static let shared = Logger()
    
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.swiftviewer.logger", qos: .utility)
    
    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.logFileURL = documents.appendingPathComponent("SwiftViewer_Debug.log")
        
        // Create file if not exists
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }
    
    func log(_ message: String) {
        queue.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            let logMessage = "[\(timestamp)] \(message)\n"
            
            print(logMessage) // Also print to stdout
            
            if let data = logMessage.data(using: .utf8) {
                if let fileHandle = try? FileHandle(forWritingTo: self.logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            }
        }
    }
    
    func clear() {
        queue.async {
            try? "".write(to: self.logFileURL, atomically: true, encoding: .utf8)
        }
    }
}
