import SwiftUI

struct ProcessingOverlay: View {
    let state: LoadingState
    
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(.ultraThinMaterial)
                .frame(width: 300, height: state.isError ? 160 : 120)
                .overlay {
                    VStack(spacing: 12) {
                        if !state.isError {
                        ProgressView()
                            .scaleEffect(1.2)
                        }
                        Text(state.message)
                            .font(.system(size: state.isError ? 15 : 16))
                            .multilineTextAlignment(.center)
                            .foregroundColor(state.isError ? .red : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                }
        }
        .transition(.opacity)
    }
} 