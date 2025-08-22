import SwiftUI

struct ProcessingOverlay: View {
    let state: LoadingState
    
    var body: some View {
        // Overlay compact et élégant
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .frame(width: 280, height: state.isError ? 140 : 100)  // Plus compact
            .overlay {
                VStack(spacing: 10) {
                    if !state.isError {
                        ProgressView()
                            .scaleEffect(1.0)  // Taille normale
                    }
                    Text(state.message)
                        .font(.system(size: state.isError ? 14 : 15))  // Plus petit
                        .multilineTextAlignment(.center)
                        .foregroundColor(state.isError ? .red : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .transition(.opacity)
    }
} 