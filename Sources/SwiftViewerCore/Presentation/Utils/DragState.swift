import Foundation

class DragState {
    static let shared = DragState()
    
    var currentDragSource: URL?
    var dragStartTime: Date?
    
    // Timeout for drag state validity (e.g., 60 seconds)
    private let timeout: TimeInterval = 60
    
    var isValid: Bool {
        guard let start = dragStartTime else { return false }
        return Date().timeIntervalSince(start) < timeout
    }
    
    private init() {}
    
    func startDrag(url: URL) {
        currentDragSource = url
        dragStartTime = Date()
    }
    
    func clear() {
        currentDragSource = nil
        dragStartTime = nil
    }
}
