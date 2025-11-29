import SwiftUI
import AppKit

public struct WindowAccessor: NSViewRepresentable {
    public var callback: (NSWindow?) -> Void
    
    public init(callback: @escaping (NSWindow?) -> Void) {
        self.callback = callback
    }
    
    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.callback(view.window)
        }
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {}
}
