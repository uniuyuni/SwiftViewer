import Foundation

class FileSystemMonitor {
    static let shared = FileSystemMonitor()
    
    private var monitorSource: DispatchSourceFileSystemObject?
    private var monitoredURL: URL?
    private var fileDescriptor: Int32 = -1
    
    private init() {}
    
    private var isSuspended: Bool = false
    private let lock = NSLock()
    
    func suspend() {
        lock.lock()
        isSuspended = true
        lock.unlock()
    }
    
    func resume() {
        lock.lock()
        isSuspended = false
        lock.unlock()
    }
    
    func startMonitoring(url: URL, onChange: @escaping () -> Void) {
        stopMonitoring()
        
        monitoredURL = url
        fileDescriptor = open(url.path, O_EVTONLY)
        
        guard fileDescriptor != -1 else { return }
        
        Logger.shared.log("FileSystemMonitor: Started monitoring \(url.path)")
        
        monitorSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: DispatchQueue.global())
        
        monitorSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            self.lock.lock()
            if self.isSuspended {
                self.lock.unlock()
                Logger.shared.log("FileSystemMonitor: Change detected but suspended. Ignoring.")
                return
            }
            self.lock.unlock()
            
            let event = self.monitorSource?.data
            Logger.shared.log("FileSystemMonitor: Change detected in \(url.path). Event: \(event?.rawValue ?? 0)")
            onChange()
        }
        
        let fd = fileDescriptor
        monitorSource?.setCancelHandler {
            close(fd)
        }
        
        monitorSource?.resume()
    }
    
    func stopMonitoring() {
        monitorSource?.cancel()
        monitorSource = nil
        // Closing is handled in cancel handler
    }
}
