import SwiftUI

struct RemarkableWordsSection: View {
    let remarkableWords: [RemarkableWord]
    let isLoading: Bool
    let onWordTap: (RemarkableWord) -> Void
    let onEditTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Titre avec bouton d'édition (toujours affiché)
            HStack {
                Text("Mots remarquables")
                    .font(.title2)
                Spacer()
                Button(action: onEditTap) {
                    Text("Éditer")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            if isLoading {
                // Indicateur de chargement moderne (sous le titre)
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Chargement des mots remarquables...")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else if remarkableWords.isEmpty {
                // Placeholder quand aucun mot remarquable
                Text("Aucun mot remarquable pour le moment")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                // Flux simple de tous les mots remarquables (triés alphabétiquement)
                WordDiscoveryView(
                    words: remarkableWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending },
                    onWordTap: onWordTap
                )
            }
        }
    }
} 