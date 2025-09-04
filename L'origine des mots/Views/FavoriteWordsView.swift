import SwiftUI

struct FavoriteWordsView: View {
    let favoriteWords: [(id: String, name: String)]
    let onWordTap: (String) -> Void
    let onRemove: (String) -> Void
    
    @State private var animatingStars: Set<String> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mes Favoris")
                .font(.title2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(favoriteWords, id: \.id) { favorite in
                        HStack(spacing: 8) {
                            Text(favorite.name)
                                .onTapGesture {
                                    onWordTap(favorite.id)
                                }
                                .accessibilityLabel("Ouvrir \(favorite.name)")
                            Button(action: { 
                                // Animation étoile : pleine bleue → vide bleue → disparition
                                let _ = withAnimation(.easeInOut(duration: 0.15)) {
                                    animatingStars.insert(favorite.id)
                                }
                                
                                // Après 150ms, supprimer définitivement
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        onRemove(favorite.id)
                                        animatingStars.remove(favorite.id)
                                    }
                                }
                            }) {
                                Image(systemName: animatingStars.contains(favorite.id) ? "star" : "star.fill")
                                    .foregroundColor(.blue)  // Toujours bleue (pleine ou vide)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .accessibilityLabel("Retirer \(favorite.name) des favoris")
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
        .padding(.bottom, 2)
    }
    
}

#Preview {
    FavoriteWordsView(
        favoriteWords: [
            (id: "1", name: "cabaret"),
            (id: "2", name: "pamplemousse"),
            (id: "3", name: "algorithme")
        ],
        onWordTap: { _ in },
        onRemove: { _ in }
    )
}
