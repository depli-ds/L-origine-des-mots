import SwiftUI

struct KilometersAddedToast: View {
    let kilometers: Double
    let wordName: String
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "location.circle.fill")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formattedKilometers) km ajoutés au total")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Text("par le mot « \(wordName) »")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        isVisible = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(radius: 8)
        )
        .padding(.horizontal)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
        .onAppear {
            // Auto-dismiss après 4 secondes
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation {
                    isVisible = false
                }
            }
        }
    }
    
    private var formattedKilometers: String {
        if kilometers < 1.0 {
            return String(format: "%.0f", kilometers * 1000) + " m"
        } else {
            return String(format: "%.1f", kilometers)
        }
    }
}

#Preview {
    ZStack {
        Color.blue.opacity(0.1)
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            KilometersAddedToast(
                kilometers: 1245.6,
                wordName: "café",
                isVisible: .constant(true)
            )
            Spacer()
        }
    }
} 