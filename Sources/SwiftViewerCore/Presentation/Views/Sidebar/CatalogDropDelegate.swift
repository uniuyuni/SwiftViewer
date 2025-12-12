
import SwiftUI
import UniformTypeIdentifiers

struct CatalogDropDelegate: DropDelegate {
    let viewModel: MainViewModel

    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.folder])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.fileURL]) else { return false }
        let providers = info.itemProviders(for: [.fileURL])
        guard let provider = providers.first else { return false }
        
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            Task { @MainActor in
                viewModel.importFolderToCatalog(url: url)
            }
        }
        return true
    }
}
