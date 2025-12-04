import SwiftUI
import AppKit

struct PersistentSplitView<Content1: View, Content2: View>: NSViewRepresentable {
    let content1: Content1
    let content2: Content2
    let autosaveName: String
    let isVertical: Bool
    let hideSecondPane: Bool
    
    init(
        autosaveName: String,
        isVertical: Bool = false,
        hideSecondPane: Bool = false,
        @ViewBuilder content1: () -> Content1,
        @ViewBuilder content2: () -> Content2
    ) {
        self.autosaveName = autosaveName
        self.isVertical = isVertical
        self.hideSecondPane = hideSecondPane
        self.content1 = content1()
        self.content2 = content2()
    }
    
    func makeNSView(context: Context) -> NSSplitView {
        print("PersistentSplitView: makeNSView called")
        let splitView = NSSplitView()
        splitView.isVertical = isVertical
        splitView.dividerStyle = .thin
        splitView.autosaveName = NSSplitView.AutosaveName(autosaveName)
        splitView.delegate = context.coordinator
        
        // Add subviews
        let view1 = NSHostingView(rootView: content1)
        let view2 = NSHostingView(rootView: content2)
        
        view1.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view2.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        splitView.addArrangedSubview(view1)
        splitView.addArrangedSubview(view2)
        
        // Restore saved position
        DispatchQueue.main.async {
            print("PersistentSplitView: Looking for saved position with key: \(self.autosaveName)")
            if let savedPosition = UserDefaults.standard.object(forKey: self.autosaveName) as? CGFloat {
                print("PersistentSplitView: Restoring position: \(savedPosition)")
                splitView.setPosition(savedPosition, ofDividerAt: 0)
                
                // Verify restore
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let actualPosition = splitView.arrangedSubviews[0].frame.width
                    print("PersistentSplitView: Actual position after restore: \(actualPosition)")
                }
            } else {
                print("PersistentSplitView: No saved position found for key: \(self.autosaveName)")
            }
            
            // Setup window close observer to save position
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nil,
                queue: .main
            ) { [weak splitView] _ in
                guard let splitView = splitView else { return }
                if splitView.arrangedSubviews.count >= 2 {
                    let position = splitView.arrangedSubviews[0].frame.width
                    print("PersistentSplitView: Saving position on window close: \(position)")
                    UserDefaults.standard.set(position, forKey: self.autosaveName)
                    UserDefaults.standard.synchronize()
                }
            }
        }
        
        return splitView
    }
    
    func updateNSView(_ splitView: NSSplitView, context: Context) {
        // Update hosting views
        if splitView.arrangedSubviews.count >= 2 {
            if let hostView1 = splitView.arrangedSubviews[0] as? NSHostingView<Content1> {
                hostView1.rootView = content1
            }
            if let hostView2 = splitView.arrangedSubviews[1] as? NSHostingView<Content2> {
                hostView2.rootView = content2
            }
            
            print("PersistentSplitView: updateNSView - hideSecondPane: \(hideSecondPane)")
            
            if hideSecondPane != context.coordinator.wasHidden {
                context.coordinator.wasHidden = hideSecondPane
                
                if hideSecondPane {
                    // Save current position before collapsing
                    let currentPosition = splitView.arrangedSubviews[0].frame.width
                    context.coordinator.savedPosition = currentPosition
                    print("PersistentSplitView: Saving current position before collapse: \(currentPosition)")
                    
                    // Collapse second pane to zero width (full width for first pane)
                    print("PersistentSplitView: Collapsing second pane to full width")
                    splitView.setPosition(splitView.bounds.width, ofDividerAt: 0)
                    
                    // Disable divider interaction
                    context.coordinator.isDividerEnabled = false
                } else {
                    // Restore previously saved position
                    print("PersistentSplitView: Expanding second pane")
                    
                    // Re-enable divider interaction
                    context.coordinator.isDividerEnabled = true
                    
                    if let savedPos = context.coordinator.savedPosition {
                        print("PersistentSplitView: Restoring position from before collapse: \(savedPos)")
                        splitView.setPosition(savedPos, ofDividerAt: 0)
                    } else if let defaultSaved = UserDefaults.standard.object(forKey: autosaveName) as? CGFloat {
                        print("PersistentSplitView: Restoring UserDefaults position: \(defaultSaved)")
                        splitView.setPosition(defaultSaved, ofDividerAt: 0)
                    } else {
                        print("PersistentSplitView: No saved position, using default 50/50 split")
                        splitView.setPosition(splitView.bounds.width * 0.5, ofDividerAt: 0)
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(autosaveName: autosaveName)
    }
    
    class Coordinator: NSObject, NSSplitViewDelegate {
        let autosaveName: String
        var wasHidden: Bool = false
        var savedPosition: CGFloat?
        var isDividerEnabled: Bool = true
        weak var splitView: NSSplitView?
        
        init(autosaveName: String) {
            self.autosaveName = autosaveName
        }
        
        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            // Disable dragging when divider is disabled
            if !isDividerEnabled {
                return splitView.arrangedSubviews[0].frame.width
            }
            
            // No minimum constraint when hiding (allow full collapse)
            if wasHidden {
                return 0
            }
            return 400 // Min width for grid pane
        }
        
        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            // Disable dragging when divider is disabled
            if !isDividerEnabled {
                return splitView.arrangedSubviews[0].frame.width
            }
            
            // No maximum constraint when hiding (allow full expansion)
            if wasHidden {
                return splitView.bounds.width
            }
            return splitView.bounds.width - 100 // Min width for preview pane
        }
        
        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            // Prevent collapsing when divider is disabled
            return false
        }
    }
}

