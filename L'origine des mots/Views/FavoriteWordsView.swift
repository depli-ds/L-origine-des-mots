import SwiftUI

struct FavoriteWordsView: View {
    let favoriteWords: [(id: String, name: String)]
    let onWordTap: (String) -> Void
    let onRemove: (String) -> Void
    
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
                                withAnimation {
                                    onRemove(favorite.id)
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .foregroundColor(.gray.opacity(0.7))
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
