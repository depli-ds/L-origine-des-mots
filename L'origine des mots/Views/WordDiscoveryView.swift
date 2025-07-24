import SwiftUI

struct WordDiscoveryView: View {
    let words: [RemarkableWord]
    let onWordTap: (RemarkableWord) -> Void
    
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(words) { word in
                Text(word.word)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .onTapGesture {
                        onWordTap(word)
                    }
            }
        }
        .padding(.horizontal)
        .padding(.leading, 16)
    }
}

#Preview {
    WordDiscoveryView(
        words: [
            RemarkableWord(
                id: UUID(),
                word: "algorithme",
                shortDescription: nil,
                tags: ["sciences", "arabe"],
                createdAt: Date()
            ),
            RemarkableWord(
                id: UUID(),
                word: "café",
                shortDescription: nil,
                tags: ["alimentation", "arabe"],
                createdAt: Date()
            )
        ],
        onWordTap: { _ in }
    )
} 