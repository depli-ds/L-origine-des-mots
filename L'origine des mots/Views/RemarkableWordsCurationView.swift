import SwiftUI

enum SortOption: String, CaseIterable {
    case alphabetical = "Alphabétique"
    case date = "Date d'ajout"
    
    var icon: String {
        switch self {
        case .alphabetical: return "textformat.abc"
        case .date: return "calendar"
        }
    }
}

struct RemarkableWordsCurationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var allWords: [Word] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var updatingWords: Set<String> = []
    @State private var errorMessage: String?
    @State private var sortOption: SortOption = .alphabetical
    @State private var refreshTrigger: Double = 0
    
    private var totalWords: Int { allWords.count }
    private var remarkableWords: Int { allWords.filter { $0.isRemarkable }.count }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    headerView
                    
                    VStack(spacing: 12) {
                        sortingView
                        searchView
                    }
                    .padding(.top, 16)
                    
                    if isLoading && allWords.isEmpty {
                        ProgressView("Chargement...")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedAndFilteredWords, id: \.id) { word in
                                ModernWordCurationRow(
                                    word: word,
                                    isUpdating: updatingWords.contains(word.id),
                                    onToggleRemarkable: { newStatus in
                                        await toggleOptimistic(for: word, newStatus: newStatus)
                                    },
                                    onDelete: {
                                        await deleteWord(word)
                                    },
                                    refreshTrigger: refreshTrigger
                                )
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                                
                                if word.id != sortedAndFilteredWords.last?.id {
                                    Divider()
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.top, 16)
                    }
                }
            }
            .navigationTitle("Curation")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { 
                        NotificationCenter.default.post(name: NSNotification.Name("CurationViewClosed"), object: nil)
                        dismiss() 
                    }
                }
            }
        }
        .task { await loadWords() }
        .alert("Erreur", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 30) {
            StatCard(title: "Total", value: "\(totalWords)", color: .blue)
            StatCard(title: "Remarquables", value: "\(remarkableWords)", color: .yellow)
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var sortingView: some View {
        HStack {
            Text("Tri par:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Picker("Tri", selection: $sortOption) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Label(option.rawValue, systemImage: option.icon)
                        .tag(option)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var searchView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Rechercher...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            if !searchText.isEmpty {
                Button("✕") { searchText = "" }
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    var sortedAndFilteredWords: [Word] {
        let filtered = searchText.isEmpty ? allWords : allWords.filter {
            $0.word.localizedCaseInsensitiveContains(searchText)
        }
        
        switch sortOption {
        case .alphabetical:
            return filtered.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        case .date:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        }
    }
    
    private func loadWords() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let words = try await SupabaseService.shared.fetchAllWordsByDate()
            await MainActor.run {
                self.allWords = words
                self.isLoading = false
                print("✅ \(words.count) mots chargés (\(remarkableWords) remarquables)")
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Erreur: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func toggleOptimistic(for word: Word, newStatus: Bool) async {
        print("🔄 Toggle '\(word.word)': \(word.isRemarkable) → \(newStatus)")
        
        // Mise à jour optimiste locale
        await MainActor.run {
            if let index = allWords.firstIndex(where: { $0.id == word.id }) {
                allWords[index] = Word(
                    id: word.id, word: word.word, etymology: word.etymology,
                    language: word.language, source: word.source,
                    createdAt: word.createdAt, updatedAt: Date(),
                    foundInCNRTL: word.foundInCNRTL, foundWithCNRTLAndClaude: word.foundWithCNRTLAndClaude,
                    isRemarkable: newStatus, shortDescription: word.shortDescription,
                    distanceKm: word.distanceKm, isComposedWord: word.isComposedWord,
                    components: word.components, gptAnalysis: word.gptAnalysis
                )
                updatingWords.insert(word.id)
            }
        }
        
        // Appel Supabase
        do {
            try await SupabaseService.shared.toggleRemarkableStatus(wordId: word.id, newStatus: newStatus)
            
            await MainActor.run {
                updatingWords.remove(word.id)
                print("✅ Toggle confirmé pour '\(word.word)'")
                
                // 🔄 Forcer le rafraîchissement des toggles
                refreshTrigger = Date().timeIntervalSince1970
                
                // Notifier la home pour synchronisation
                NotificationCenter.default.post(
                    name: NSNotification.Name("RemarkableWordUpdated"),
                    object: nil,
                    userInfo: ["wordId": word.id, "isRemarkable": newStatus, "word": word.word]
                )
                print("📢 NOTIFICATION: Envoi de RemarkableWordUpdated pour '\(word.word)' (isRemarkable: \(newStatus))")
                
            }
            
            // 🔄 CORRECTION: Recharger la curation après toggle réussi avec délai
            print("🔄 Rechargement de la curation après toggle...")
            print("⏳ Attente de 1s pour propagation complète...")
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 seconde
            
            // Vider TOUT le cache Supabase pour forcer le rechargement
            await SupabaseService.shared.clearCache()
            await loadWords()
            
        } catch {
            print("❌ Erreur toggle '\(word.word)': \(error)")
            // Revert en cas d'erreur
            await MainActor.run {
                if let index = allWords.firstIndex(where: { $0.id == word.id }) {
                    allWords[index] = Word(
                        id: word.id, word: word.word, etymology: word.etymology,
                        language: word.language, source: word.source,
                        createdAt: word.createdAt, updatedAt: word.updatedAt,
                        foundInCNRTL: word.foundInCNRTL, foundWithCNRTLAndClaude: word.foundWithCNRTLAndClaude,
                        isRemarkable: !newStatus, shortDescription: word.shortDescription,
                        distanceKm: word.distanceKm, isComposedWord: word.isComposedWord,
                        components: word.components, gptAnalysis: word.gptAnalysis
                    )
                }
                updatingWords.remove(word.id)
                errorMessage = "Erreur: \(error.localizedDescription)"
            }
        }
    }
    
    private func deleteWord(_ word: Word) async {
        print("🗑️ Suppression du mot '\(word.word)'...")
        
        _ = await MainActor.run {
            updatingWords.insert(word.id)
        }
        
        do {
            try await SupabaseService.shared.deleteWord(wordId: word.id)
            print("✅ Mot '\(word.word)' supprimé avec succès")
            
            // Recharger après suppression
            await loadWords()
            
            // Notifier la home
                        _ = await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("RemarkableWordUpdated"),
                    object: nil,
                    userInfo: ["deleted": true, "word": word.word]
                )
            }
            
        } catch {
            print("❌ Erreur suppression '\(word.word)': \(error)")
            _ = await MainActor.run {
                updatingWords.remove(word.id)
                errorMessage = "Erreur lors de la suppression: \(error.localizedDescription)"
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)).shadow(radius: 1))
    }
}

struct ModernWordCurationRow: View {
    let word: Word
    let isUpdating: Bool
    let onToggleRemarkable: (Bool) async -> Void
    let onDelete: () async -> Void
    let refreshTrigger: Double
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(word.word)
                        .font(.headline)
                        .foregroundColor(word.isRemarkable ? .primary : .secondary)
                    
                    Spacer()
                    
                    Text(formatDate(word.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 12) {
                    // Kilomètres AVANT nombre d'étapes
                    if let distanceKm = word.distanceKm {
                        Label("\(Int(distanceKm)) km", systemImage: "location")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Label("\(word.etymology.chain.count) étapes", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                if !word.etymology.chain.isEmpty {
                    HStack {
                        Text("\(word.etymology.chain.first?.language ?? "?") → \(word.etymology.chain.last?.language ?? "?")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                }
            }
            
            VStack(spacing: 8) {
                // Toggle calé en haut à droite
                VStack {
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 44, height: 28)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { word.isRemarkable },
                            set: { newValue in
                                Task { await onToggleRemarkable(newValue) }
                            }
                        ))
                        .labelsHidden()
                        .scaleEffect(0.9)
                        .id("\(word.id)-\(word.isRemarkable)-\(word.updatedAt.timeIntervalSince1970)")
                    }
                    
                    Spacer() // Pousse le toggle vers le haut
                }
                
                // Bouton supprimer
                Button(action: {
                    Task { await onDelete() }
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.1))
                        )
                }
                .disabled(isUpdating)
                .opacity(isUpdating ? 0.3 : 1.0)
            }
        }
        .padding(.vertical, 8)
        .opacity(isUpdating ? 0.7 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(word.isRemarkable ? Color.yellow.opacity(0.1) : Color.clear)
                .animation(.easeInOut(duration: 0.2), value: word.isRemarkable)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
} 