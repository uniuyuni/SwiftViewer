import CoreData
import SwiftUI

struct CatalogManagerView: View {
    @StateObject private var viewModel = CatalogViewModel()
    @State private var newCatalogName = ""
    @State private var isCreating = false
    @Binding var selectedCatalog: Catalog?
    var isImporting: Bool = false
    
    @State private var showDeleteAlert = false
    @State private var catalogToDelete: Catalog?
    
    @State private var showRenameAlert = false
    @State private var catalogToRename: Catalog?
    @State private var renameText = ""
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        content
            .frame(width: 400, height: 500)
            .onReceive(NotificationCenter.default.publisher(for: .coreDataStackChanged)) { _ in
                viewModel.reloadFromCurrentStore()
            }
    }
    
    private var content: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            catalogList
            Divider()
            footerView
        }
    }

    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 12) {
                    Button {
                        NotificationCenter.default.post(name: .requestNewCatalog, object: nil)
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .disabled(isImporting)

                    Button {
                        NotificationCenter.default.post(name: .requestOpenCatalog, object: nil)
                    } label: {
                        Label("Open", systemImage: "folder")
                    }
                    .disabled(isImporting)
                }

                Spacer()
                Text("Manage Catalogs")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var footerView: some View {
        HStack {
            ImeAwareTextField(
                placeholder: "New Catalog Name",
                text: $newCatalogName,
                onSubmit: { createCatalog() }
            )
            Button("Create") {
                createCatalog()
            }
            .disabled(newCatalogName.isEmpty)
        }

        .padding()
        .alert("Rename Catalog", isPresented: $showRenameAlert, presenting: catalogToRename) { catalog in
            TextField("New Name", text: $renameText)
            Button("Rename") {
                viewModel.renameCatalog(catalog, newName: renameText)
            }
            Button("Cancel", role: .cancel) {}
        } message: { catalog in
            Text("Enter a new name for '\(catalog.name ?? "Untitled")'.")
        }
    }
    
    private var catalogList: some View {
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
                Button("Rename") {
                    catalogToRename = catalog
                    renameText = catalog.name ?? ""
                    showRenameAlert = true
                }
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
    }
    
    private func createCatalog() {
        let trimmed = newCatalogName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let created = viewModel.createCatalog(name: trimmed) {
            selectedCatalog = created
        }
        newCatalogName = ""
    }
}

// MARK: - IME誤作動対策つき TextField（Returnで作成）
//
// 日本語IMEの変換確定(Enter)で誤って onSubmit が走らないよう、
// 「markedText（変換中テキスト）が無い」ことを確認してから Return を処理する。
private struct ImeAwareTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }
    
    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField(string: text)
        tf.placeholderString = placeholder
        tf.isBezeled = true
        tf.bezelStyle = .roundedBezel
        tf.isBordered = true
        tf.drawsBackground = true
        tf.delegate = context.coordinator
        return tf
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }
    
    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onSubmit: () -> Void
        
        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }
        
        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            text = tf.stringValue
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Returnキーを押した時だけ処理（IME変換確定中のEnterは hasMarkedText() で弾く）
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if textView.hasMarkedText() {
                    return false // IME変換確定として扱う（誤作動防止）
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return false }
                onSubmit()
                return true
            }
            return false
        }
    }
}
