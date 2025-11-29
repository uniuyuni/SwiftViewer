import SwiftUI
import CoreData

@MainActor
class ImportViewModel: ObservableObject {
    @Published var selectedFiles: [URL] = []
    @Published var isImporting = false
    @Published var progress: Double = 0
    
    private let mediaRepository: MediaRepositoryProtocol
    let catalog: Catalog
    
    init(catalog: Catalog, mediaRepository: MediaRepositoryProtocol = MediaRepository()) {
        self.catalog = catalog
        self.mediaRepository = mediaRepository
    }
    
    func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false // User requested folder selection only
        // panel.allowedContentTypes = [.image, .movie] // Not needed for folders
        
        if panel.runModal() == .OK {
            self.selectedFiles = panel.urls
        }
    }
    
    func triggerImport(mainViewModel: MainViewModel) {
        for url in selectedFiles {
            mainViewModel.importFolderToCatalog(url: url)
        }
        selectedFiles = []
    }
}
