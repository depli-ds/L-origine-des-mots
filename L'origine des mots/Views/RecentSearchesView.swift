import SwiftUI

struct RecentSearchesView: View {
    let recentSearches: [String]
    let onWordTap: (String) -> Void
    let onRemove: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Historique")
                .font(.title2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentSearches, id: \.self) { word in
                        HStack(spacing: 8) {
                            Text(word)
                                .onTapGesture {
                                    onWordTap(word)
                                }
                                .accessibilityLabel("Rechercher \(word)")
                            Button(action: { 
                                withAnimation {
                                    onRemove(word)
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .foregroundColor(.gray.opacity(0.7))
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .accessibilityLabel("Supprimer \(word) de l'historique")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 40)
    }
}

#Preview {
    RecentSearchesView(
        recentSearches: ["algorithme", "café", "kiosque"],
        onWordTap: { _ in },
        onRemove: { _ in }
    )
} 