import SwiftUI

public struct SettingsView: View {
    public init() {}
    
    private enum Tabs: Hashable {
        case general, appearance
    }
    
    public var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tabs.general)
            
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette")
                }
                .tag(Tabs.appearance)
        }
        .padding(20)
        .frame(width: 375, height: 150)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("defaultAppMode") private var defaultAppMode: String = "folders"
    
    var body: some View {
        Form {
            Picker("Start in:", selection: $defaultAppMode) {
                Text("Folders").tag("folders")
                Text("Catalogs").tag("catalogs")
            }
            
            Section("Maintenance") {
                Button("Clear Thumbnail Cache") {
                    ThumbnailCacheService.shared.clearCache()
                    ImageCacheService.shared.clearCache()
                }
            }
        }
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("defaultThumbnailSize") private var defaultThumbnailSize: Double = 100.0
    
    var body: some View {
        Form {
            Slider(value: $defaultThumbnailSize, in: 50...300) {
                Text("Default Thumbnail Size")
            } minimumValueLabel: {
                Text("Small")
            } maximumValueLabel: {
                Text("Large")
            }
        }
        .padding()
    }
}
