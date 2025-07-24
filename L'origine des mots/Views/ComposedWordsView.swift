import SwiftUI

struct ComposedWordsView: View {
    let composedWord: Word
    @Binding var isPresented: Bool
    @State private var componentWords: [Word] = []
    @State private var isLoadingComponents = true
    @State private var showingMap = false
    @State private var selectedWordForMap: Word?
    @State private var showingSources = false
    @State private var selectedWordForSources: Word?
    @Environment(\.dismiss) private var dismiss
    
    init(composedWord: Word, isPresented: Binding<Bool>) {
        self.composedWord = composedWord
        self._isPresented = isPresented
        print("🔧 DEBUG ComposedWordsView init - composedWord: \(composedWord.word)")
        print("🔧 DEBUG ComposedWordsView init - components: \(composedWord.components)")
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // En-tête 
                    HStack {
                        Spacer()
                        Text("Origine du mot composé :")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { 
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.gray)
                        }
                        .padding(.leading, -40)
                    }
                    
                    // D'abord l'étymologie du mot composé lui-même
                    VStack(spacing: 20) {
                        Text(composedWord.word)
                            .font(.system(size: 40, weight: .medium))
                        
                        ForEach(Array(composedWord.etymology.chain.enumerated()), id: \.element.language) { cardIndex, entry in
                            EtymologyCard(entry: entry)
                            
                            if cardIndex < composedWord.etymology.chain.count - 1 {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: 1, height: 50)
                            }
                        }
                        
                        // Boutons d'action pour le mot composé
                        HStack(spacing: 20) {
                            if composedWord.hasGeographicalJourney {
                                Button(action: { 
                                    selectedWordForMap = composedWord
                                    showingMap = true 
                                }) {
                                    Label("Voir le voyage du mot", systemImage: "map.fill")
                                        .foregroundColor(.blue)
                                }
                                
                                Spacer()
                                
                                Button(action: { 
                                    selectedWordForSources = composedWord
                                    showingSources = true 
                                }) {
                                    Label("Sources", systemImage: "text.book.closed.fill")
                                        .foregroundColor(.blue)
                                }
                            } else {
                                Spacer()
                                
                                Button(action: { 
                                    selectedWordForSources = composedWord
                                    showingSources = true 
                                }) {
                                    Label("Sources", systemImage: "text.book.closed.fill")
                                        .foregroundColor(.blue)
                                }
                                
                                Spacer()
                            }
                        }
                        .padding(.top, 20)
                        
                        WordDistanceFooter(word: composedWord)
                    }
                    
                    // Séparateur avant les composants
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                        .padding(.horizontal, 40)
                    
                    // Section des composants
                    if isLoadingComponents {
                        ProgressView("Chargement des composants...")
                            .padding(.vertical, 40)
                    } else if componentWords.isEmpty {
                        VStack(spacing: 16) {
                            Text("Composants détectés :")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            ForEach(composedWord.components.indices, id: \.self) { index in
                                Text("• \(composedWord.components[index])")
                                    .font(.system(size: 16))
                                    .foregroundColor(.primary)
                            }
                            
                            Text("(Composants disponibles sans étymologie détaillée)")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        .padding(.vertical, 20)
                    } else {
                        // Affichage de chaque composant avec son étymologie
                        ForEach(Array(componentWords.enumerated()), id: \.offset) { index, word in
                            VStack(spacing: 20) {
                                Text(word.word)
                                    .font(.system(size: 40, weight: .medium))
                                
                                ForEach(Array(word.etymology.chain.enumerated()), id: \.element.language) { cardIndex, entry in
                                    EtymologyCard(entry: entry)
                                    
                                    if cardIndex < word.etymology.chain.count - 1 {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.4))
                                            .frame(width: 1, height: 50)
                                    }
                                }
                                
                                // Boutons d'action pour chaque composant
                                HStack(spacing: 20) {
                                    if word.hasGeographicalJourney {
                                        Button(action: { 
                                            selectedWordForMap = word
                                            showingMap = true 
                                        }) {
                                            Label("Voir le voyage du mot", systemImage: "map.fill")
                                                .foregroundColor(.blue)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: { 
                                            selectedWordForSources = word
                                            showingSources = true 
                                        }) {
                                            Label("Sources", systemImage: "text.book.closed.fill")
                                                .foregroundColor(.blue)
                                        }
                                    } else {
                                        Spacer()
                                        
                                        Button(action: { 
                                            selectedWordForSources = word
                                            showingSources = true 
                                        }) {
                                            Label("Sources", systemImage: "text.book.closed.fill")
                                                .foregroundColor(.blue)
                                        }
                                        
                                        Spacer()
                                    }
                                }
                                .padding(.top, 20)
                                
                                WordDistanceFooter(word: word)
                            }
                            
                            // Séparateur entre les composants (sauf pour le dernier)
                            if index < componentWords.count - 1 {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                                    .padding(.horizontal, 40)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingMap) {
                if let selectedWord = selectedWordForMap {
                    EtymologyMapView(word: selectedWord)
                }
            }
            .sheet(isPresented: $showingSources) {
                if let selectedWord = selectedWordForSources {
                    SourcesView(word: selectedWord)
                }
            }
            .onAppear {
                loadComponentWords()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
    }
    
    private func loadComponentWords() {
        Task {
            var fetchedWords: [Word] = []
            
            for component in composedWord.components {
                do {
                    if let componentWord = try await SupabaseService.shared.fetchWord(component) {
                        fetchedWords.append(componentWord)
                        print("✅ Composant '\(component)' trouvé avec étymologie")
                        print("🔍 DEBUG - Mot retourné: '\(componentWord.word)'")
                        print("🔍 DEBUG - Étymologie: \(componentWord.etymology.chain.count) étapes")
                        for (index, entry) in componentWord.etymology.chain.enumerated() {
                            print("  \(index + 1). \(entry.language): \(entry.sourceWord)")
                        }
                        print("🔍 DEBUG - Distance: \(componentWord.distanceKm?.description ?? "nil") km")
                        print("🔍 DEBUG - hasGeographicalJourney: \(componentWord.hasGeographicalJourney)")
                        print("🔍 DEBUG - isComposedWord: \(componentWord.isComposedWord)")
                    } else {
                        print("⚠️ Composant '\(component)' non trouvé en base - ignoré pour l'instant")
                    }
                } catch {
                    print("❌ Erreur lors de la recherche du composant '\(component)': \(error)")
                }
            }
            
            await MainActor.run {
                componentWords = fetchedWords
                isLoadingComponents = false
            }
        }
    }
}
