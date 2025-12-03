import SwiftUI
import CoreData

@MainActor
class CatalogViewModel: ObservableObject {
    @Published var catalogs: [Catalog] = []
    @Published var currentCatalog: Catalog?
    
    private let repository: CatalogRepositoryProtocol
    
    init(repository: CatalogRepositoryProtocol = CatalogRepository()) {
        self.repository = repository
        loadCatalogs()
    }
    
    func loadCatalogs() {
        do {
            catalogs = try repository.fetchCatalogs()
        } catch {
            print("Failed to fetch catalogs: \(error)")
        }
    }
    
    func createCatalog(name: String) {
        do {
            let newCatalog = try repository.createCatalog(name: name)
            catalogs.append(newCatalog)
            currentCatalog = newCatalog
        } catch {
            print("Failed to create catalog: \(error)")
        }
    }
    
    func deleteCatalog(_ catalog: Catalog) {
        do {
            try repository.deleteCatalog(catalog)
            if let index = catalogs.firstIndex(of: catalog) {
                catalogs.remove(at: index)
            }
            if currentCatalog == catalog {
                currentCatalog = nil
            }
        } catch {
            print("Failed to delete catalog: \(error)")
        }
    }
    
    func renameCatalog(_ catalog: Catalog, newName: String) {
        do {
            try repository.renameCatalog(catalog, newName: newName)
            loadCatalogs()
        } catch {
            print("Failed to rename catalog: \(error)")
        }
    }
}
