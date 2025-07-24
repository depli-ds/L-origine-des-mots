import SwiftUI

struct ProcessingOverlay: View {
    let state: LoadingState
    
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(.ultraThinMaterial)
                .frame(width: 280, height: 120)
                .overlay {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(state.message)
                            .font(.system(size: 16))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                    }
                    .padding()
                }
        }
        .transition(.opacity)
    }
} 