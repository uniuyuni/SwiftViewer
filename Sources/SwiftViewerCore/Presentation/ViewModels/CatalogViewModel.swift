import SwiftUI
import CoreData

@MainActor
class CatalogViewModel: ObservableObject {
    @Published var catalogs: [Catalog] = []
    @Published var currentCatalog: Catalog?
    
    private var repository: CatalogRepositoryProtocol

    init(repository: CatalogRepositoryProtocol? = nil) {
        self.repository = repository ?? CatalogRepository()
        loadCatalogs()
    }

    /// Rebind to the current Core Data stack (e.g. after opening another catalog package).
    func reloadFromCurrentStore() {
        repository = CatalogRepository(context: PersistenceController.shared.container.viewContext)
        loadCatalogs()
    }
    
    func loadCatalogs() {
        do {
            catalogs = try repository.fetchCatalogs()
        } catch {
            print("Failed to fetch catalogs: \(error)")
        }
    }
    
    @discardableResult
    func createCatalog(name: String) -> Catalog? {
        do {
            let newCatalog = try repository.createCatalog(name: name)
            catalogs.append(newCatalog)
            currentCatalog = newCatalog
            return newCatalog
        } catch {
            print("Failed to create catalog: \(error)")
            return nil
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
