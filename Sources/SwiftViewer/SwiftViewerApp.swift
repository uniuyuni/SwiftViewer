import SwiftUI
import SwiftViewerCore
import AppKit

@main
struct SwiftViewerApp: App {
    @Environment(\.openWindow) var openWindow
    
    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindow()
        }
        .commands {
            SidebarCommands() // Enables View -> Toggle Sidebar
            
            CommandMenu("View Options") {
                InspectorToggleMenuButton()
            }
            
            CommandMenu("Tools") {
                Button("Advanced Copy") {
                    activateOrOpenAdvancedCopy()
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Refresh All") {
                    NotificationCenter.default.post(name: .refreshAll, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(0xF708)!)), modifiers: [])
            }
        }
        
        Settings {
            SettingsView()
        }
    }

    
    private func activateOrOpenAdvancedCopy() {
        // Check if window is already open
        let windows = NSApplication.shared.windows
        if let existing = windows.first(where: { $0.title == "Advanced Copy" }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            // Programmatic Window Creation
            let view = AdvancedCopyView()
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "Advanced Copy"
            window.setContentSize(NSSize(width: 900, height: 600))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            
            window.center()
            window.setFrameAutosaveName("AdvancedCopyWindow")
            window.isReleasedWhenClosed = false
            
            window.makeKeyAndOrderFront(nil)
        }
    }
}

struct InspectorToggleMenuButton: View {
    @FocusedValue(\.toggleInspector) var toggleInspector
    
    var body: some View {
        Button("Toggle Inspector") {
            toggleInspector?()
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
        .disabled(toggleInspector == nil)
    }
}
