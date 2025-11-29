import SwiftUI

struct CatalogManagerView: View {
    @StateObject private var viewModel = CatalogViewModel()
    @State private var newCatalogName = ""
    @State private var isCreating = false
    @Binding var selectedCatalog: Catalog?
    
    @State private var showDeleteAlert = false
    @State private var catalogToDelete: Catalog?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {

        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Text("Manage Catalogs")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            List(viewModel.catalogs, id: \.id) { catalog in
                HStack {
                    Image(systemName: "book.closed")
                    Text(catalog.name ?? "Untitled")
                    Spacer()
                    if selectedCatalog?.objectID == catalog.objectID {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedCatalog = catalog
                }
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        catalogToDelete = catalog
                        showDeleteAlert = true
                    }
                }
            }
            .listStyle(.plain)
            .alert("Delete Catalog?", isPresented: $showDeleteAlert, presenting: catalogToDelete) { catalog in
                Button("Delete", role: .destructive) {
                    viewModel.deleteCatalog(catalog)
                    if selectedCatalog?.objectID == catalog.objectID {
                        selectedCatalog = nil
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { catalog in
                Text("Are you sure you want to delete '\(catalog.name ?? "Untitled")'? This action cannot be undone.")
            }
            
            Divider()
            
            HStack {
                TextField("New Catalog Name", text: $newCatalogName)
                    .textFieldStyle(.roundedBorder)
                Button("Create") {
                    guard !newCatalogName.isEmpty else { return }
                    viewModel.createCatalog(name: newCatalogName)
                    newCatalogName = ""
                }
                .disabled(newCatalogName.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
    }
}
