import AppKit
import Quartz

public class QuickLookService: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = QuickLookService()
    
    private var currentURLs: [URL] = []
    private var panel: QLPreviewPanel?
    
    private override init() {
        super.init()
    }
    
    public func toggleQuickLook(for urls: [URL]) {
        self.currentURLs = urls
        
        if let panel = QLPreviewPanel.shared() {
            self.panel = panel
            
            if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
                panel.orderOut(nil)
            } else {
                panel.dataSource = self
                panel.delegate = self
                panel.makeKeyAndOrderFront(nil)
                panel.reloadData()
            }
        }
    }
    
    // MARK: - QLPreviewPanelDataSource
    
    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return currentURLs.count
    }
    
    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0 && index < currentURLs.count else { return nil }
        return currentURLs[index] as QLPreviewItem
    }
    
    // MARK: - QLPreviewPanelDelegate
    
    public func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Handle key events if needed, e.g. arrow keys to navigate
        // For now, let default handling work or return false
        return false
    }
    
    public func windowWillClose(_ notification: Notification) {
        // Cleanup if needed
        self.panel = nil
    }
}
