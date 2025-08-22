import SwiftUI
import Combine

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .center,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

@MainActor
struct ContentView: View {
    @State private var searchText = ""
    @State private var selectedWord: Word?
    @State private var showingEtymology = false
    @State private var loadingState: LoadingState = .idle
    @State private var searchHistory: [String] = UserDefaults.standard.stringArray(forKey: "searchHistory") ?? []
    @State private var remarkableWords: [RemarkableWord] = []
    @State private var isLoadingRemarkableWords = false
    @State private var composedWords: [Word] = []
    @State private var showingComposedWords = false
    @State private var showingCuration = false
    
    @FocusState private var isSearchFieldFocused: Bool
    @StateObject private var curator = RemarkableWordsCurator.shared
    @Environment(\.colorScheme) var colorScheme
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let wordToSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        isSearchFieldFocused = false
        
        Task {
            do {
                await MainActor.run {
                    loadingState = .loadingWord
                }
                
                // Vérifier si le mot existe déjà
                if let existingWord = try await SupabaseService.shared.fetchWord(wordToSearch) {
                    await MainActor.run {
                        loadingState = .idle
                        addToHistory(wordToSearch)
                        
                        if existingWord.isComposedWord && existingWord.components.count >= 2 {
                            composedWords = [existingWord]
                            showingComposedWords = true
                        } else {
                            selectedWord = existingWord
                            showingEtymology = true
                        }
                    }
                } else {
                    // Mot non trouvé - création
                    await MainActor.run {
                        loadingState = .analyzingWord
                    }
                    
                    let newWord = try await EtymologyOrchestrator.shared.processNewWord(wordToSearch)
                    
                    await MainActor.run {
                        loadingState = .idle
                        addToHistory(wordToSearch)
                        
                        if newWord.isComposedWord && newWord.components.count >= 2 {
                            composedWords = [newWord]
                            showingComposedWords = true
                        } else {
                            selectedWord = newWord
                            showingEtymology = true
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    // Gestion spécifique des différents types d'erreurs
                    if let cnrtlError = error as? CNRTLError {
                        switch cnrtlError {
                        case .wordNotFound:
                            loadingState = .error("Aucune correspondance trouvée pour '\(wordToSearch)'")
                        case .sectionNotFound:
                            loadingState = .error("Pas de résultat disponible pour '\(wordToSearch)'")
                        default:
                            loadingState = .error("Erreur de connexion lors de la recherche")
                        }
                    } else if let etymologyError = error as? EtymologyError {
                        loadingState = .error(etymologyError.localizedDescription)
                    } else {
                        // Vérifier les types d'erreurs spécifiques
                        let errorMessage = error.localizedDescription.lowercased()
                        
                        if errorMessage.contains("introuvable") || 
                           errorMessage.contains("non trouvé") ||
                           errorMessage.contains("not found") {
                            loadingState = .error("Aucune correspondance trouvée pour '\(wordToSearch)'")
                        } else if errorMessage.contains("timed out") || errorMessage.contains("timeout") {
                            loadingState = .error("Délai d'attente dépassé\nClaude et GPT-5 sont temporairement surchargés.\nRéessayez dans quelques minutes.")
                        } else if errorMessage.contains("overloaded") {
                            loadingState = .error("Services IA temporairement surchargés\nRéessayez dans quelques instants.")
                        } else {
                            loadingState = .error("Erreur: \(error.localizedDescription)")
                        }
                    }
                }
            }
            
            // Délai pour laisser l'utilisateur voir qu'une recherche a eu lieu
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconde

            await MainActor.run {
                // Effacer le champ de recherche pour indiquer qu'il n'y a pas de résultat
                searchText = ""
            }
        }
    }
    
    private func addToHistory(_ word: String) {
        if !searchHistory.contains(word) {
            searchHistory.insert(word, at: 0)
            if searchHistory.count > 10 {
                searchHistory.removeLast()
            }
            UserDefaults.standard.set(searchHistory, forKey: "searchHistory")
        }
    }
    
    private func loadRemarkableWords() async {
        await MainActor.run {
            isLoadingRemarkableWords = true
        }
        
        do {
            print("🔄 Chargement des mots remarquables depuis la base...")
            let words = try await SupabaseService.shared.fetchRemarkableWords()
            await MainActor.run {
                remarkableWords = words
                isLoadingRemarkableWords = false
            }
            print("✅ \(words.count) mots remarquables chargés")
        } catch {
            print("❌ Erreur lors de la récupération des mots remarquables: \(error)")
            await MainActor.run {
                remarkableWords = []
                isLoadingRemarkableWords = false
            }
            print("✅ 0 mots remarquables récupérés (erreur)")
        }
    }
    
    private func reopenWordFromHistory(_ word: String) async {
        // Mettre à jour le champ de recherche avec le mot sélectionné
        await MainActor.run {
            searchText = word
            isSearchFieldFocused = false
        }
        
        do {
            let foundWord = try await SupabaseService.shared.fetchWord(word)
            
            if let word = foundWord {
                await MainActor.run {
                    addToHistory(word.word)
                    
                    print("🔍 DEBUG reopenWordFromHistory - Mot '\(word.word)':")
                    print("   - isComposedWord: \(word.isComposedWord)")
                    print("   - components.count: \(word.components.count)")
                    print("   - components: \(word.components)")
                    
                    if word.isComposedWord && word.components.count >= 2 {
                        print("✅ Affichage ComposedWordsView pour '\(word.word)'")
                        composedWords = [word]
                        showingComposedWords = true
                        print("🔧 DEBUG: showingComposedWords = \(showingComposedWords)")
                    } else {
                        print("✅ Affichage EtymologyResultView pour '\(word.word)'")
                        selectedWord = word
                        showingEtymology = true
                    }
                }
            } else {
                // Mot non trouvé - lancer une nouvelle recherche
                print("⚠️ Mot '\(word)' non trouvé en base, recherche via orchestrateur...")
                performSearch()
            }
        } catch {
            // En cas d'erreur, lancer une nouvelle recherche
            print("❌ Erreur lors de la recherche de '\(word)': \(error)")
            performSearch()
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                mainScrollView
                
                // Calque opaque fixe pour status bar (au-dessus du scroll)
                VStack {
                    Rectangle()
                        .fill(Color(.systemBackground))
                        .frame(height: 20)
                        .ignoresSafeArea(edges: .top)
                    Spacer()
                }
                .allowsHitTesting(false)
                
                if loadingState.isLoading {
                    ProcessingOverlay(state: loadingState)
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .onTapGesture {
                // Tap en dehors pour défocaliser
                if isSearchFieldFocused {
                    isSearchFieldFocused = false
                }
            }
            .onAppear {
                setupOnAppear()
                
                // Connecter le callback de loading pour EtymologyOrchestrator
                EtymologyOrchestrator.shared.onLoadingStateChange = { newState in
                    Task { @MainActor in
                        loadingState = newState
                    }
                }
            }
        }
        .sheet(isPresented: etymologySheetBinding) {
            if let word = selectedWord {
                EtymologyResultView(etymology: word.etymology, word: word)
            }
        }
        .sheet(isPresented: $showingComposedWords) {
            if let composedWord = composedWords.first {
                ComposedWordsView(
                    composedWord: composedWord,
                    isPresented: $showingComposedWords
                )
                .onAppear {
                    print("🔧 DEBUG: Sheet ComposedWordsView appelée - composedWord: \(composedWord.word)")
                }
            } else {
                Text("Aucun mot composé")
                    .onAppear {
                        print("🔧 DEBUG: Pas de mots composés à afficher")
                    }
            }
        }
        .sheet(isPresented: $showingCuration) {
            RemarkableWordsCurationView()
        }
        // SUPPRIMÉ: Rechargement automatique après ajout de nouveaux mots
        // .onReceive(curator.$newWordsAdded) { newWords in
        //     if !newWords.isEmpty {
        //         Task {
        //             await loadRemarkableWords()
        //         }
        //         curator.clearNewWordsNotification()
        //     }
        // }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CurationViewClosed"))) { _ in
            Task {
                // Forcer le vidage du cache pour éviter les désynchronisations
                await SupabaseService.shared.clearRemarkableWordsCache()
                await loadRemarkableWords()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RemarkableWordUpdated"))) { notification in
            Task {
                print("📨 CONTENTVIEW: Notification RemarkableWordUpdated reçue!")
                if let userInfo = notification.userInfo, let word = userInfo["word"] as? String, let isRemarkable = userInfo["isRemarkable"] as? Bool {
                    print("📨 CONTENTVIEW: Mot '\(word)' isRemarkable=\(isRemarkable)")
                }
                
                // 🔄 CORRECTION: Attendre la propagation Supabase avant rechargement
                print("⏳ CONTENTVIEW: Attente de 1s pour propagation Supabase...")
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 seconde
                
                // Vider COMPLÈTEMENT le cache Supabase avant rechargement
                await SupabaseService.shared.clearCache()
                await loadRemarkableWords()
                print("📨 CONTENTVIEW: Rechargement terminé")
            }
        }
// SUPPRIMÉ:         .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WordDeleted"))) { _ in
// SUPPRIMÉ:             Task {
// SUPPRIMÉ:                 await loadRemarkableWords()
// SUPPRIMÉ:             }
// SUPPRIMÉ:         }
    }
    
    // MARK: - Computed Properties
    private var etymologySheetBinding: Binding<Bool> {
        Binding(
            get: { showingEtymology && selectedWord != nil },
            set: { newValue in 
                if !newValue {
                    showingEtymology = false
                }
            }
        )
    }
    
    private var mainScrollView: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    AppHeaderView()
                    
                    // Spacer pour centrer verticalement le champ de recherche
                    Spacer()
                        .frame(height: max(60, (geometry.size.height - 200) / 3))
                    
                    // Champ de recherche centré verticalement
                    searchSection
                    
                    // Grand espace avant l'historique et les mots remarquables
                    Spacer()
                        .frame(height: max(60, (geometry.size.height - 200) / 3))
                    
                    if !searchHistory.isEmpty {
                        RecentSearchesView(
                            recentSearches: searchHistory,
                            onWordTap: { word in
                                Task {
                                    await reopenWordFromHistory(word)
                                }
                            },
                            onRemove: { word in
                                if let index = searchHistory.firstIndex(of: word) {
                                    searchHistory.remove(at: index)
                                    UserDefaults.standard.set(searchHistory, forKey: "searchHistory")
                                }
                            }
                        )
                        
                        // Petit espace entre historique et mots remarquables
                        Spacer()
                            .frame(height: 8)
                    }
                    
                    RemarkableWordsSection(
                        remarkableWords: remarkableWords,
                        isLoading: isLoadingRemarkableWords,
                        onWordTap: { remarkableWord in
                            Task {
                                await reopenWordFromHistory(remarkableWord.word)
                            }
                        },
                        onEditTap: {
                            showingCuration = true
                        }
                    )
                    .id("remarkable-words-\(remarkableWords.count)-\(remarkableWords.map { $0.id.uuidString }.joined(separator: "-"))")
                    
                    AppFooterView()
                }
                .frame(minHeight: geometry.size.height)
            }
        }
    }
    
    private var searchSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                // Zone de texte centrée avec bouton X intégré
                HStack {
                    Spacer()
                    
                    // Conteneur VERTICAL avec texte en haut et loupe en dessous
                    VStack(spacing: 16) {
                        // Zone de texte avec X à droite
                        HStack {
                            Spacer()
                            
                            // Zone de texte avec placeholder
                            ZStack {
                                // Placeholder "Rechercher" quand vide et non focalisé
                                if !isSearchFieldFocused && searchText.isEmpty {
                                    Text("Rechercher")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(.secondary.opacity(0.3))
                                        .allowsHitTesting(false)
                                }
                                
                                // TextField pour la saisie
                                TextField("", text: $searchText)
                                    .focused($isSearchFieldFocused)
                                    .font(.system(size: 40, weight: .medium))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .onSubmit {
                                        performSearch()
                                    }
                                    .onTapGesture {
                                        isSearchFieldFocused = true
                                    }
                            }
                            
                            // Bouton X À DROITE
                            if !searchText.isEmpty {
                                Button(action: {
                                    searchText = ""
                                }) {
                                    Image(systemName: "xmark")
                                        .foregroundColor(.gray.opacity(0.7))
                                        .font(.system(size: 16, weight: .medium))
                                }
                            } else {
                                Spacer()
                                    .frame(width: 20) // Espace pour équilibrer même sans X
                            }
                        }
                        
                        // Loupe EN DESSOUS dans le bloc
                        Button(action: {
                            performSearch()
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.3 : 1.0)
                        
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                (colorScheme == .dark ? Color.black : Color.white)
                                    .shadow(.inner(
                                        color: colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.1),
                                        radius: 15,  // MÊME radius que les cartes
                                        x: 0,
                                        y: 8
                                    ))
                            )
                    )
                    
                    Spacer()
                }

            }
            .padding(.horizontal, 24)  // MÊME que les cartes : 24px des bords
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Helper Methods
    private func setupOnAppear() {
        // Vider l'historique au démarrage
        searchHistory = []
        UserDefaults.standard.set([], forKey: "searchHistory")
        
        // SUPPRIMÉ: Focus automatique pour une interface plus sobre
        // DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        //     isSearchFieldFocused = true
        // }
        
        // Vider le cache puis charger les mots remarquables
        Task {
            await SupabaseService.shared.clearAllCaches()
            await loadRemarkableWords()
        }
    }
    

}

#Preview {
    ContentView()
}