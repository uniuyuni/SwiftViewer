import SwiftUI
import SwiftViewerCore
import AppKit

@main
struct SwiftViewerApp: App {
    @Environment(\.openWindow) var openWindow
    
    init() {
        CatalogService.shared.loadDefaultCatalog()
    }
    
    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindow()
        }
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands() // Enables View -> Toggle Sidebar
            
            CommandMenu("View Options") {
                InspectorToggleMenuButton()
            }
            
            CommandMenu("Tools") {
                AdvancedCopyMenuButton(action: activateOrOpenAdvancedCopy)
                
                Divider()
                
                Button("Refresh All") {
                    NotificationCenter.default.post(name: .refreshAll, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(0xF708)!)), modifiers: [])
                
                Divider()
                
                UpdateCatalogMenuButton()
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
        .keyboardShortcut("i", modifiers: [])
        .disabled(toggleInspector == nil)
    }
}

struct UpdateCatalogMenuButton: View {
    @FocusedValue(\.updateCatalog) var updateCatalog
    
    var body: some View {
        Button("Update Catalog") {
            updateCatalog?()
        }
        .disabled(updateCatalog == nil)
    }
}

struct AdvancedCopyMenuButton: View {
    let action: () -> Void
    @FocusedValue(\.isFullScreen) var isFullScreen
    
    var body: some View {
        Button("Advanced Copy") {
            action()
        }
        .keyboardShortcut("K", modifiers: [.command, .shift])
        .disabled(isFullScreen == true)
    }
}
