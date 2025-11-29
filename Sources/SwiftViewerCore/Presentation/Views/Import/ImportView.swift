import SwiftUI

struct ImportView: View {
    @StateObject var viewModel: ImportViewModel
    @ObservedObject var mainViewModel: MainViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Text("Import to \(viewModel.catalog.name ?? "Catalog")")
                .font(.headline)
                .padding()
            
            List(viewModel.selectedFiles, id: \.self) { url in
                Text(url.lastPathComponent)
            }
            
            if viewModel.isImporting {
                ProgressView(value: viewModel.progress)
                    .padding()
            }
            
            HStack {
                Button("Select Folders...") {
                    viewModel.selectFiles()
                }
                .disabled(viewModel.isImporting)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .disabled(viewModel.isImporting)
                
                Button("Import") {
                    // Delegate to MainViewModel for consistent UI (pending imports in sidebar)
                    viewModel.triggerImport(mainViewModel: mainViewModel)
                    dismiss()
                }
                .disabled(viewModel.selectedFiles.isEmpty || viewModel.isImporting)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}
