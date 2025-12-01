import SwiftUI

struct BlockingOperationView: View {
    let message: String
    let progress: Double // 0.0 to 1.0, or < 0 for indeterminate
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
            
            // Dialog
            VStack(spacing: 20) {
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                if progress >= 0 {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(radius: 20)
            )
        }
    }
}
