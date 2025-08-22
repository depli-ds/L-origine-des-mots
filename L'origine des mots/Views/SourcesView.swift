import SwiftUI

struct SourcesView: View {
    let word: Word?
    let context: SourceContext
    @Environment(\.dismiss) private var dismiss
    
    enum SourceContext {
        case mainWord        // Mot principal
        case component       // Composant d'un mot composé
    }
    
    init(word: Word? = nil, context: SourceContext = .mainWord) {
        self.word = word
        self.context = context
    }
    
    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 12) {
                    switch context {
                    case .mainWord:
                        Text("Sources des étymologies :")
                            .font(.headline)
                            .padding(.bottom, 4)
                    case .component:
                        Text("Sources du composant :")
                            .font(.headline)
                            .padding(.bottom, 4)
                    }
                    
                    // Lien spécifique au mot si fourni ET trouvé dans CNRTL
                    if let word = word, word.foundInCNRTL {
                        Link("• Voir le mot \(word.word) sur CNRTL", 
                             destination: URL(string: "https://www.cnrtl.fr/etymologie/\(word.word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word.word)")!)
                            .foregroundColor(.blue)
                            .font(.system(size: 16))
                            .padding(.bottom, 8)
                    }
                    
                    // Messages contextuels
                    if let word = word, !word.foundInCNRTL && word.source == "Analyse composée" {
                        switch context {
                        case .mainWord:
                            Text("• Mot analysé via décomposition étymologique")
                                .foregroundColor(.orange)
                                .font(.system(size: 16))
                                .padding(.bottom, 8)
                        case .component:
                            Text("• Composant virtuel créé pour l'analyse du mot parent")
                                .foregroundColor(.orange)
                                .font(.system(size: 16))
                                .padding(.bottom, 8)
                        }
                    }
                    
                    Link("• CNRTL - Centre National de Ressources Textuelles et Lexicales", 
                         destination: URL(string: "https://www.cnrtl.fr")!)
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                    
                    Text("Les étymologies sont recherchées automatiquement dans cette source académique.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    Text("L'analyse sémantique et géographique est effectuée par IA (Claude Sonnet 4).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            }
        }
    }
} 