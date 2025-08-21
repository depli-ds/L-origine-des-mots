import SwiftUI

enum Tab {
    case etymology
    case source
}

struct EtymologyResultView: View {
    let etymology: DirectEtymology
    let word: Word
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showingMap = false
    @State private var showingSources = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                HStack {
                    Spacer()
                    Text("Origine du mot :")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    .padding(.leading, -40)
                }
                
                Text(word.word)
                    .font(.system(size: 40, weight: .medium))
                
                ForEach(Array(etymology.chain.enumerated()), id: \.offset) { index, entry in
                    EtymologyCard(entry: entry)
                    
                    if index < etymology.chain.count - 1 {
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 1, height: 50)
                    }
                }
                
                HStack(spacing: 20) {
                    // Afficher le bouton seulement s'il y a un voyage géographique potentiel
                    if word.hasGeographicalJourney {
                        Button(action: { showingMap = true }) {
                            Label("Voir le voyage du mot", systemImage: "map.fill")
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        Button(action: { showingSources = true }) {
                            Label("Sources", systemImage: "text.book.closed.fill")
                                .foregroundColor(.blue)
                        }
                    } else {
                        // Centrer le bouton sources quand pas de voyage
                        Spacer()
                        
                        Button(action: { showingSources = true }) {
                            Label("Sources", systemImage: "text.book.closed.fill")
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                    }
                }
                .padding(.top, 40)
                
                // Section des composants pour les mots composés
                if word.isComposedWord && !word.components.isEmpty {
                    ComposedWordsSection(word: word)
                }
                
                WordDistanceFooter(word: word)
            }
            .padding(24)
        }
        .sheet(isPresented: $showingMap) {
            EtymologyMapView(word: word)
        }
        .sheet(isPresented: $showingSources) {
            SourcesView(word: word)
        }
    }
}

struct EtymologyCard: View {
    let entry: EtymologyEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            Text(entry.sourceWord)
                .font(.system(size: 40, weight: .light))
            
            HStack(spacing: 8) {
                Text(entry.language)
                Text("•").font(.system(size: 12))
                if let period = entry.period {
                    Text(period)
                }
            }
            .foregroundColor(.gray)
            .font(.system(size: 18, weight: .light))
            
            if let script = entry.originalScript {
                Text(script)
                    .font(.system(size: 28))
                    .foregroundColor(.gray)
                    .padding(.top, 4)
            }
            
            if let translation = entry.translation {
                Text("« \(translation) »")
                    .foregroundColor(.gray)
                    .font(.system(size: 16, weight: .light))
                    .italic()
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color.black : Color.white)
                .shadow(
                    color: colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.1),
                    radius: 15
                )
        )
    }
}

// MARK: - Section des mots composés
struct ComposedWordsSection: View {
    let word: Word
    @State private var componentWords: [Word] = []
    @State private var isLoading = true
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            // Titre de la section
            Text("Composants de ce mot :")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.top, 20)
            
            if isLoading {
                ProgressView("Recherche des composants...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else if componentWords.isEmpty {
                // Section supprimée - pas d'affichage pour les composants sans étymologie
                EmptyView()
            } else {
                // Affichage des composants avec leurs étymologies
                ForEach(Array(componentWords.enumerated()), id: \.element.id) { index, componentWord in
                    VStack(spacing: 16) {
                        Text("Composant : \(componentWord.word)")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                        
                        ForEach(Array(componentWord.etymology.chain.enumerated()), id: \.offset) { cardIndex, entry in
                            EtymologyCard(entry: entry)
                            
                            if cardIndex < componentWord.etymology.chain.count - 1 {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 1, height: 30)
                            }
                        }
                    }
                    
                    if index < componentWords.count - 1 {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 1)
                            .padding(.horizontal, 40)
                    }
                }
            }
        }
        .onAppear {
            loadComponentWords()
        }
    }
    
    private func loadComponentWords() {
        Task {
            var fetchedWords: [Word] = []
            
            for component in word.components {
                do {
                    if let componentWord = try await SupabaseService.shared.fetchWord(component) {
                        fetchedWords.append(componentWord)
                        print("✅ Composant '\(component)' trouvé avec étymologie")
                    } else {
                        print("⚠️ Composant '\(component)' non trouvé en base")
                    }
                } catch {
                    print("❌ Erreur lors de la recherche du composant '\(component)': \(error)")
                }
            }
            
            await MainActor.run {
                componentWords = fetchedWords
                isLoading = false
            }
        }
    }
} 