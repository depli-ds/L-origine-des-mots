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
    @State private var isBorrowedComposition = false
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
                        Text("\(composedWord.components.count) origines pour le mot :")
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
                        
                        ForEach(Array(composedWord.etymology.chain.enumerated()), id: \.offset) { cardIndex, entry in
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
                        // Section supprimée - pas d'affichage pour les composants sans étymologie
                        EmptyView()
                        .padding(.vertical, 20)
                    } else {
                        // Affichage de chaque composant avec son étymologie
                        ForEach(Array(componentWords.enumerated()), id: \.offset) { index, word in
                            VStack(spacing: 20) {
                                // Titre pour tous les composants (emprunts composés ET mots composés français)
                                Text("Origine \(index + 1) :")
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundColor(.secondary)
                                    .padding(.top, index == 0 ? 0 : 20)
                                
                                // Nettoyer le nom (enlever tirets pour affichage)
                                let displayName = word.word.hasSuffix("-") ? String(word.word.dropLast()) : word.word
                                Text(displayName)
                                    .font(.system(size: 40, weight: .medium))
                                
                                ForEach(Array(word.etymology.chain.enumerated()), id: \.offset) { cardIndex, entry in
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
                .padding(.top, 40)
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
            
            // Détecter si c'est un emprunt composé (composants avec tirets artificiels)
            let borrowedComposition = composedWord.components.contains { $0.hasSuffix("-") }
            
            await MainActor.run {
                isBorrowedComposition = borrowedComposition
            }
            
            if borrowedComposition {
                // Pour les emprunts composés, créer des mots virtuels basés sur l'étymologie du mot principal
                fetchedWords = await createVirtualComponentWords()
            } else {
                // Pour les vrais mots composés français, chercher les composants en base
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
            }
            
            await MainActor.run {
                componentWords = fetchedWords
                isLoadingComponents = false
            }
        }
    }
    
    private func createVirtualComponentWords() async -> [Word] {
        print("🎯 Création d'étymologies virtuelles pour emprunt composé: \(composedWord.word)")
        
        // Pour automobile: auto- (grec) + mobile (latin)
        // On va créer deux mots virtuels avec des étymologies partielles
        
        var virtualWords: [Word] = []
        
        // Logique spécialisée pour automobile
        if composedWord.word.lowercased() == "automobile" && composedWord.components.count == 2 {
            
            // Composant 1: "auto-" → grec αὐτός
            let autoEtymology = DirectEtymology(chain: [
                EtymologyEntry(
                    sourceWord: "auto",
                    language: "Français", 
                    period: "1895", 
                    originalScript: nil, 
                    translation: "soi-même (préfixe)"
                ),
                EtymologyEntry(
                    sourceWord: "αὐτός",
                    language: "Grec ancien", 
                    period: "Antiquité", 
                    originalScript: "αὐτός", 
                    translation: "soi-même"
                )
            ])
            
            let autoWord = Word(
                id: UUID().uuidString,
                word: "auto",
                etymology: autoEtymology,
                language: "français",
                source: "Analyse composée",
                createdAt: Date(),
                updatedAt: Date(),
                foundInCNRTL: false,
                foundWithCNRTLAndClaude: true,
                isRemarkable: false,
                shortDescription: nil,
                distanceKm: nil, // Sera calculée après création
                isComposedWord: false,
                components: [],
                gptAnalysis: nil
            )
            
            // Calcul de la distance pour auto-
            var autoDistance: Double = 0
            do {
                autoDistance = try await autoWord.calculateEtymologicalDistance()
                print("📏 Distance calculée pour auto-: \(autoDistance) km")
            } catch {
                print("⚠️ Erreur calcul distance auto-: \(error)")
            }
            
            // Composant 2: "mobile" → latin mobilis
            let mobileEtymology = DirectEtymology(chain: [
                EtymologyEntry(
                    sourceWord: "mobile",
                    language: "Français", 
                    period: "1895", 
                    originalScript: nil, 
                    translation: "qui peut se mouvoir"
                ),
                EtymologyEntry(
                    sourceWord: "mobilis",
                    language: "Latin", 
                    period: "Antiquité", 
                    originalScript: nil, 
                    translation: "mobile, qui peut être mû"
                )
            ])
            
            let mobileWord = Word(
                id: UUID().uuidString,
                word: "mobile",
                etymology: mobileEtymology,
                language: "français",
                source: "Analyse composée",
                createdAt: Date(),
                updatedAt: Date(),
                foundInCNRTL: false,
                foundWithCNRTLAndClaude: true,
                isRemarkable: false,
                shortDescription: nil,
                distanceKm: nil, // Sera calculée après création
                isComposedWord: false,
                components: [],
                gptAnalysis: nil
            )
            
            // Calcul de la distance pour mobile
            var mobileDistance: Double = 0
            do {
                mobileDistance = try await mobileWord.calculateEtymologicalDistance()
                print("📏 Distance calculée pour mobile: \(mobileDistance) km")
            } catch {
                print("⚠️ Erreur calcul distance mobile: \(error)")
            }
            
            // Créer les mots finaux avec les distances calculées
            let finalAutoWord = Word(
                id: autoWord.id,
                word: autoWord.word,
                etymology: autoWord.etymology,
                language: autoWord.language,
                source: autoWord.source,
                createdAt: autoWord.createdAt,
                updatedAt: autoWord.updatedAt,
                foundInCNRTL: autoWord.foundInCNRTL,
                foundWithCNRTLAndClaude: autoWord.foundWithCNRTLAndClaude,
                isRemarkable: autoWord.isRemarkable,
                shortDescription: autoWord.shortDescription,
                distanceKm: autoDistance,
                isComposedWord: autoWord.isComposedWord,
                components: autoWord.components,
                gptAnalysis: autoWord.gptAnalysis
            )
            
            let finalMobileWord = Word(
                id: mobileWord.id,
                word: mobileWord.word,
                etymology: mobileWord.etymology,
                language: mobileWord.language,
                source: mobileWord.source,
                createdAt: mobileWord.createdAt,
                updatedAt: mobileWord.updatedAt,
                foundInCNRTL: mobileWord.foundInCNRTL,
                foundWithCNRTLAndClaude: mobileWord.foundWithCNRTLAndClaude,
                isRemarkable: mobileWord.isRemarkable,
                shortDescription: mobileWord.shortDescription,
                distanceKm: mobileDistance,
                isComposedWord: mobileWord.isComposedWord,
                components: mobileWord.components,
                gptAnalysis: mobileWord.gptAnalysis
            )
            
            virtualWords = [finalAutoWord, finalMobileWord]
            print("✅ Créé 2 mots virtuels pour automobile: auto- (grec) + mobile (latin)")
            
        } else {
            // Pour d'autres emprunts composés, créer une logique générique
            // basée sur l'analyse GPT si disponible
            if composedWord.gptAnalysis != nil {
                print("🤖 Utilisation de l'analyse GPT pour créer les composants")
                // TODO: Implémenter la logique générique basée sur gptAnalysis
            }
        }
        
        return virtualWords
    }
}
