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
    @State private var favoriteWords: [String: String] = {
        if let data = UserDefaults.standard.data(forKey: "favoriteWords"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            return decoded
        }
        // Migration depuis l'ancien format Set<String>
        let oldFavorites = UserDefaults.standard.stringArray(forKey: "favoriteWords") ?? []
        var migrated: [String: String] = [:]
        for id in oldFavorites {
            migrated[id] = "Mot favori" // Nom par défaut pour migration
        }
        return migrated
    }()
    @State private var favoriteWordsDisplay: [(id: String, name: String)] = []
    @State private var reportedWords: [ReportedWord] = {
        if let data = UserDefaults.standard.data(forKey: "reportedWords"),
           let decoded = try? JSONDecoder().decode([ReportedWord].self, from: data) {
            return decoded
        }
        // Migration depuis l'ancien format Set<String>
        let oldReports = UserDefaults.standard.stringArray(forKey: "reportedWords") ?? []
        return oldReports.map { ReportedWord(id: $0, wordName: "Mot signalé", reportDate: Date()) }
    }()
    @State private var remarkableWords: [RemarkableWord] = []
    @State private var isLoadingRemarkableWords = false
    @State private var composedWords: [Word] = []
    @State private var showingComposedWords = false
    @State private var showingCuration = false
    
    @FocusState private var isSearchFieldFocused: Bool
    @StateObject private var curator = RemarkableWordsCurator.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showNoResultMessage = false
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let wordToSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        withAnimation(.easeInOut(duration: 0.3)) {
        isSearchFieldFocused = false
        }
        
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
                            // Afficher le message "aucun résultat" après un délai
                            showNoResultAfterDelay()
                        case .sectionNotFound:
                            loadingState = .error("Pas de résultat disponible pour '\(wordToSearch)'")
                            // Afficher le message "aucun résultat" après un délai
                            showNoResultAfterDelay()
                        default:
                            loadingState = .error("Erreur de connexion lors de la recherche")
                        }
                    } else if let etymologyError = error as? EtymologyError {
                        loadingState = .error(etymologyError.localizedDescription)
                        showNoResultAfterDelay()
                    } else {
                        // Vérifier les types d'erreurs spécifiques
                        let errorMessage = error.localizedDescription.lowercased()
                        
                        if errorMessage.contains("introuvable") || 
                           errorMessage.contains("non trouvé") ||
                           errorMessage.contains("not found") {
                            loadingState = .error("Aucune correspondance trouvée pour '\(wordToSearch)'")
                            showNoResultAfterDelay()
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
    
    // MARK: - Gestion des favoris et signalements
    
    private func toggleFavorite(for word: Word) async {
        let wordId = word.id
        
        if favoriteWords[wordId] != nil {
            // Retirer des favoris
            favoriteWords.removeValue(forKey: wordId)
        } else {
            // Ajouter aux favoris (stocker ID + nom)
            favoriteWords[wordId] = word.word
            
            // Aussi incrémenter le compteur en base
            do {
                _ = try await SupabaseService.shared.toggleFavorite(for: wordId)
            } catch {
                print("❌ Erreur lors de la mise à jour des favoris: \(error)")
                // Rollback en cas d'erreur
                favoriteWords.removeValue(forKey: wordId)
            }
        }
        
        // Sauvegarder localement (nouveau format JSON)
        if let encoded = try? JSONEncoder().encode(favoriteWords) {
            UserDefaults.standard.set(encoded, forKey: "favoriteWords")
        }
        
        // Recharger l'affichage des favoris
        Task {
            await loadFavoriteWordsDisplay()
        }
    }
    
    private func getReportButtonState(for word: Word) -> ReportButtonState {
        guard let report = reportedWords.first(where: { $0.id == word.id }) else {
            return .notReported
        }
        
        // Si le mot a été mis à jour après le signalement → Corrigé
        if word.updatedAt > report.reportDate {
            return .corrected
        } else {
            return .reported
        }
    }
    
    private func toggleReport(for word: Word) async {
        let wordId = word.id
        
        if let existingIndex = reportedWords.firstIndex(where: { $0.id == wordId }) {
            // Annuler le signalement
            reportedWords.remove(at: existingIndex)
            print("🔄 Signalement annulé pour '\(word.word)'")
        } else {
            // Signaler le mot (nouveau ou re-signalement après correction)
            let newReport = ReportedWord(
                id: wordId,
                wordName: word.word,
                reportDate: Date()
            )
            reportedWords.append(newReport)
            print("📝 Nouveau signalement pour '\(word.word)'")
            
            // Aussi incrémenter le compteur en base
            do {
                _ = try await SupabaseService.shared.reportWord(for: wordId)
            } catch {
                print("❌ Erreur lors du signalement: \(error)")
                // Rollback en cas d'erreur
                if let rollbackIndex = reportedWords.firstIndex(where: { $0.id == wordId }) {
                    reportedWords.remove(at: rollbackIndex)
                }
            }
        }
        
        // Sauvegarder localement (nouveau format JSON)
        if let encoded = try? JSONEncoder().encode(reportedWords) {
            UserDefaults.standard.set(encoded, forKey: "reportedWords")
        }
    }
    
    private func loadFavoriteWordsDisplay() async {
        var favoriteDisplay: [(id: String, name: String)] = []
        
        for (wordId, wordName) in favoriteWords {
            do {
                if let word = try await SupabaseService.shared.fetchWord(byId: wordId) {
                    // ✅ Mot existe toujours
                    favoriteDisplay.append((id: wordId, name: word.word))
                } else {
                    // ⚠️ Mot orphelin → Garder avec nom stocké (sera géré au tap)
                    favoriteDisplay.append((id: wordId, name: wordName))
                    print("⚠️ Favori orphelin détecté: '\(wordName)' (ID: \(wordId))")
                }
            } catch {
                // ⚠️ Erreur → Garder avec nom stocké
                favoriteDisplay.append((id: wordId, name: wordName))
                print("❌ Erreur chargement favori '\(wordName)' (ID: \(wordId)): \(error)")
            }
        }
        
        await MainActor.run {
            favoriteWordsDisplay = favoriteDisplay
        }
    }
    
    private func removeFavorite(_ wordId: String) {
        favoriteWords.removeValue(forKey: wordId)
        if let encoded = try? JSONEncoder().encode(favoriteWords) {
            UserDefaults.standard.set(encoded, forKey: "favoriteWords")
        }
        favoriteWordsDisplay.removeAll { $0.id == wordId }
    }
    
    private func handleFavoriteTap(_ favoriteId: String) async {
        do {
            if let word = try await SupabaseService.shared.fetchWord(byId: favoriteId) {
                // ✅ Mot existe → Ouvrir normalement
                print("✅ Favori '\(word.word)' trouvé, ouverture directe")
                await reopenWordFromHistory(word.word)
            } else {
                // ⚠️ Orphelin → Recherche silencieuse via le champ
                if let wordName = favoriteWords[favoriteId] {
                    print("🔄 Favori orphelin détecté: '\(wordName)' → Recherche complète")
                    await MainActor.run {
                        searchText = wordName
                        isSearchFieldFocused = false // Pas de focus clavier
                    }
                    performSearch() // Passe par toute la logique de recherche
                }
            }
        } catch {
            // ⚠️ Erreur → Fallback sur recherche
            if let wordName = favoriteWords[favoriteId] {
                print("🔄 Erreur favori '\(wordName)' → Fallback recherche")
                await MainActor.run {
                    searchText = wordName
                    isSearchFieldFocused = false
                }
                performSearch()
            }
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
            withAnimation(.easeInOut(duration: 0.3)) {
                isSearchFieldFocused = false
            }
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
                
                // Plus de compensation status bar - mode plein écran
                
                // Loading maintenant intégré dans le bloc de recherche
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            // Respect de la safe area pour éviter de taper dans le menu
            .onTapGesture {
                // Tap en dehors pour défocaliser
                if isSearchFieldFocused {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isSearchFieldFocused = false
                    }
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
                EtymologyResultView(
                    etymology: word.etymology, 
                    word: word,
                    onToggleFavorite: { word in
                        await toggleFavorite(for: word)
                    },
                    onToggleReport: { word in
                        await toggleReport(for: word)
                    },
                    isFavorite: favoriteWords[word.id] != nil,
                    reportButtonState: getReportButtonState(for: word)
                )
            }
        }
        .sheet(isPresented: $showingComposedWords) {
            if let composedWord = composedWords.first {
                ComposedWordsView(
                    composedWord: composedWord,
                    isPresented: $showingComposedWords,
                    onToggleFavorite: { word in
                        await toggleFavorite(for: word)
                    },
                    onToggleReport: { word in
                        await toggleReport(for: word)
                    },
                    isFavorite: favoriteWords[composedWord.id] != nil,
                    reportButtonState: getReportButtonState(for: composedWord)
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
                    
                    // Spacer pour centrer le champ de recherche (égal à celui d'après)
                        Spacer()
                        .frame(height: max(40, (geometry.size.height - 400) / 6))
                    
                    // Champ de recherche centré verticalement
                    searchSection
                    
                    // Espace modéré avant l'historique  
                    Spacer()
                        .frame(height: max(40, (geometry.size.height - 400) / 6))
                    
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
                        
                        // Espace équilibré entre historique et favoris
                        Spacer()
                            .frame(height: 16)
                    }
                    
                    // Section Favoris
                    if !favoriteWordsDisplay.isEmpty {
                        FavoriteWordsView(
                            favoriteWords: favoriteWordsDisplay,
                            onWordTap: { favoriteId in
                                Task {
                                    await handleFavoriteTap(favoriteId)
                                }
                            },
                            onRemove: { favoriteId in
                                removeFavorite(favoriteId)
                            }
                        )
                        
                        // Espace équilibré entre favoris et mots remarquables
                        Spacer()
                            .frame(height: 16)
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
        VStack(spacing: 6) {   // Réduit encore pour ergonomie mobile
            VStack(spacing: 8) {   // Titre plus proche pour compacité
                // Titre en dehors du bloc (comme "Origine du mot:")
                Text("Chercher un mot :")
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(.secondary)
                
                // Zone de texte centrée avec bouton X en overlay + loading intégré
                VStack(spacing: 16) {
                    ZStack {
                        // Zone de texte avec X en overlay (vraiment centré)
                        ZStack {
                            // TextField parfaitement centré (prend toute la largeur)
                            ZStack {
                                // Placeholder "Rechercher" simple et cohérent
                                if !isSearchFieldFocused && searchText.isEmpty && !loadingState.isLoading && !showNoResultMessage {
                                    Text("Rechercher")
                                        .font(.system(size: 40, weight: .light))
                                        .foregroundColor(.secondary.opacity(0.6))  // Meilleur contraste WCAG
                                        .allowsHitTesting(false)
                                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                }
                                
                                // TextField pour la saisie
                                TextField("", text: $searchText)
                                    .focused($isSearchFieldFocused)
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .disabled(loadingState.isLoading)  // Désactiver pendant loading
                                    .onSubmit {
                                        performSearch()
                                    }
                                    .onTapGesture {
                                        if !loadingState.isLoading {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                isSearchFieldFocused = true
                                            }
                                        }
                                    }
                            }
                            
                            // Bouton X en overlay absolu (ne décale RIEN)
                            if !searchText.isEmpty && !loadingState.isLoading && !showNoResultMessage && loadingState == .idle {
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        searchText = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray.opacity(0.6))
                                            .font(.system(size: 18))  // Plus petit pour meilleur alignement
                                    }
                                    .frame(width: 44, height: 44)  // Zone de tap recommandée Apple (44pt)
                                    .contentShape(Rectangle())  // Zone de tap rectangulaire plus grande
                                    .offset(y: 2)  // Descendre pour aligner en bout de ligne
                                }
                                .padding(.trailing, 6)
                            }
                        }
                        
                    }
                        
                    // Zone fixe pour loupe OU loading OU message aucun résultat (hauteur constante)
                    ZStack {
                        if showNoResultMessage {
                            // Message "Aucun résultat trouvé" dans la même zone que les autres messages
                            Text("Aucun résultat trouvé")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .frame(height: 32)  // Même hauteur que loading
                        } else if loadingState.isLoading {
                            // Loading à la place de la loupe
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.9)
                                Text(loadingState.message)
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(height: 32)  // Hauteur fixe
                        } else if case .error = loadingState {
                            // État d'erreur : on ne montre RIEN (prépare pour message "aucun résultat")
                    Spacer()
                                .frame(height: 32)  // Garde la hauteur mais vide
                        } else {
                            // Loupe quand pas de loading
                            Button(action: {
                                performSearch()
                            }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.secondary.opacity(0.6))  // Même gris que placeholder
                            }
                            .frame(height: 32)  // Même hauteur fixe
                            .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            // Pas d'opacity supplémentaire pour garder bon contraste
                        }
                    }
                        
                }
                .padding(.horizontal, 20)  // MÊME padding interne que les cartes
                .padding(.vertical, 32)    // Plus haut que les cartes pour intégrer loading
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            (colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                                .shadow(.inner(
                                    color: colorScheme == .dark ? .white.opacity(0.2) : .black.opacity(0.1),
                                    radius: 15,  // MÊME radius que les cartes
                                    x: 0,
                                    y: 8
                                ))
                        )
                )
                .ignoresSafeArea(.keyboard)  // Bloc fixe quand clavier apparaît
                // HITBOX ÉTENDUE : Tap sur tout le rectangle lance la recherche
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .onTapGesture {
                    // Prioriser focus si vide, sinon rechercher
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSearchFieldFocused = true
                        }
                    } else if !loadingState.isLoading {
                        performSearch()
                    }
                }
                
                Spacer()

            }
            .padding(.horizontal, 24)  // MÊME que les cartes : 24px des bords
            .padding(.top, 16)      // Réduit encore pour ergonomie mobile optimale
            .padding(.bottom, 4)    // Espace vraiment réduit pour remonter historique
        }
    }
    
    private func showNoResultAfterDelay() {
        // Afficher le message "aucun résultat" PLUS RAPIDEMENT
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // CUT simple sans animation de fondu
            showNoResultMessage = true
            // NE PAS changer loadingState ici pour éviter flash loupe/X
            
            // Reset complet après affichage du message (1.5 secondes)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showNoResultMessage = false
                loadingState = .idle  // Reset loadingState SEULEMENT à la fin
                // Vider le champ pour repartir proprement
                searchText = ""
            }
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
        
        // Vider le cache puis charger les mots remarquables et favoris
        Task {
            await SupabaseService.shared.clearAllCaches()
            await loadRemarkableWords()
            await loadFavoriteWordsDisplay()
        }
    }
    

}

#Preview {
    ContentView()
}