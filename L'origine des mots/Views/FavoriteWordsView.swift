import SwiftUI

struct FavoriteWordsView: View {
    let favoriteWords: [String]
    let onWordTap: (String) -> Void
    let onRemove: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mes Favoris")
                .font(.title2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(favoriteWords, id: \.self) { wordId in
                        HStack(spacing: 8) {
                            Text(displayWord(for: wordId))
                                .onTapGesture {
                                    onWordTap(wordId)
                                }
                                .accessibilityLabel("Ouvrir \(displayWord(for: wordId))")
                            Button(action: { 
                                withAnimation {
                                    onRemove(wordId)
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .foregroundColor(.gray.opacity(0.7))
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .accessibilityLabel("Retirer \(displayWord(for: wordId)) des favoris")
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
    
    private func displayWord(for wordId: String) -> String {
        // Pour l'instant on affiche l'ID, mais on pourrait récupérer le mot depuis la base
        return wordId
    }
}

#Preview {
    FavoriteWordsView(
        favoriteWords: ["cabaret", "pamplemousse", "algorithme"],
        onWordTap: { _ in },
        onRemove: { _ in }
    )
}
