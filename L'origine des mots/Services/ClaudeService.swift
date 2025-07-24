import Foundation

@globalActor actor ClaudeActor {
    static let shared = ClaudeActor()
}

@ClaudeActor
class ClaudeService: @unchecked Sendable {
    static let shared = ClaudeService()
    
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    
    private init() {
        // Ajoutez votre clé Anthropic dans Configuration.swift
        self.apiKey = Configuration.anthropicKey
    }
    
    func analyzeEtymology(_ text: String, knownLanguages: [String]) async throws -> EtymologyAnalysis {
        let prompt = EtymologyPrompts.etymologyAnalysis
            .replacingOccurrences(of: "{etymology_text}", with: text)
            .replacingOccurrences(of: "{known_languages}", with: knownLanguages.joined(separator: ", "))
        
        print("\n🤖 Envoi du prompt à Claude :")
        print("📝 Longueur: \(prompt.count) caractères")
        
        let response = try await sendMessage(prompt)
        
        // Extraire le JSON depuis la réponse markdown de Claude
        let cleanedResponse = extractJSONFromMarkdown(response)
        print("🧹 JSON extrait:", cleanedResponse)
        
        let decoder = JSONDecoder()
        let analysis = try decoder.decode(EtymologyAnalysis.self, from: cleanedResponse.data(using: .utf8)!)
        
        // Validation : rejeter les entrées avec "NEW_LANGUAGE" et déduplication
        let validChain = analysis.etymology.chain.filter { entry in
            if entry.language == "NEW_LANGUAGE" {
                print("❌ Entrée rejetée avec NEW_LANGUAGE: \(entry.sourceWord)")
                return false
            }
            return true
        }
        
        // Déduplication : supprimer les doublons de mots et de langues
        let deduplicatedChain = deduplicateEtymologyChain(validChain)
        
        return EtymologyAnalysis(
            etymology: GPTEtymology(chain: deduplicatedChain),
            is_composed_word: analysis.is_composed_word,
            components: analysis.components,
            new_languages: analysis.new_languages
        )
    }
    
    func analyzeHistoricalLanguages(_ languages: [String]) async throws -> [LanguageAnalysis] {
        let prompt = EtymologyPrompts.historicalLanguages
            .replacingOccurrences(of: "{languages}", with: languages.joined(separator: ", "))
        
        print("\n🏛️ Analyse des langues historiques avec Claude")
        print("📝 Langues à analyser: \(languages.joined(separator: ", "))")
        
        let response = try await sendMessage(prompt)
        
        // Extraire le JSON depuis la réponse markdown de Claude
        let cleanedResponse = extractJSONFromMarkdown(response)
        
        let decoder = JSONDecoder()
        let result = try decoder.decode([LanguageAnalysis].self, from: cleanedResponse.data(using: .utf8)!)
        
        print("✅ \(result.count) langues analysées")
        return result
    }
    
    func sendMessage(_ prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
                let requestBody: [String: Any] = [
             "model": "claude-sonnet-4-20250514",
             "max_tokens": 4000,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        
        print("📊 Code HTTP Claude: \(httpResponse.statusCode)")
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("🔍 Réponse brute Claude:")
            print(responseString)
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ Erreur Claude: \(errorString)")
            }
            throw ServiceError.httpError(httpResponse.statusCode)
        }
        
        // Décoder la réponse Claude
        struct ClaudeResponse: Codable {
            let content: [ClaudeContent]
        }
        
        struct ClaudeContent: Codable {
            let text: String
        }
        
        let decoder = JSONDecoder()
        let claudeResponse = try decoder.decode(ClaudeResponse.self, from: data)
        
        guard let content = claudeResponse.content.first?.text else {
            throw ServiceError.noData
        }
        
        print("📥 Réponse de Claude:")
        print(content)
        print("📏 Longueur de la réponse: \(content.count) caractères\n")
        
        return content
    }
    
    func analyzeCuration(_ prompt: String) async throws -> CurationResponse {
        print("\n🎯 Analyse de curation avec Claude")
        
        let response = try await sendMessage(prompt)
        
        // Extraire le JSON depuis la réponse markdown de Claude
        let cleanedResponse = extractJSONFromMarkdown(response)
        print("🧹 JSON de curation extrait:", cleanedResponse)
        
        let decoder = JSONDecoder()
        guard let data = cleanedResponse.data(using: .utf8) else {
            throw ServiceError.invalidResponse
        }
        let curationResult = try decoder.decode(CurationResponse.self, from: data)
        
        print("✅ \(curationResult.selected_words.count) mots sélectionnés par Claude")
        return curationResult
    }
    
    // Fonction pour extraire le JSON depuis le markdown de Claude
    private func extractJSONFromMarkdown(_ response: String) -> String {
        // Claude retourne souvent le JSON entre ```json et ```
        if let startRange = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            let jsonStart = startRange.upperBound
            let jsonEnd = endRange.lowerBound
            return String(response[jsonStart..<jsonEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Si pas de balises markdown, retourner tel quel
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Déduplication intelligente par date d'entrée
    private func deduplicateEtymologyChain(_ chain: [EtymologyEntry]) -> [EtymologyEntry] {
        guard !chain.isEmpty else { return [] }
        
        print("🧹 Déduplication intelligente de \(chain.count) entrées:")
        for (index, entry) in chain.enumerated() {
            print("   \(index + 1). \(entry.language):\(entry.sourceWord) (\(entry.period ?? "date inconnue"))")
        }
        
        // ✅ NOUVELLE LOGIQUE: Garder l'entrée la plus ancienne pour chaque langue
        var languageGroups: [String: [EtymologyEntry]] = [:]
        
        // Grouper par langue
        for entry in chain {
            let language = entry.language.trimmingCharacters(in: .whitespacesAndNewlines)
            if languageGroups[language] == nil {
                languageGroups[language] = []
            }
            languageGroups[language]?.append(entry)
        }
        
        // Pour chaque langue, garder l'entrée avec la date la plus ancienne
        var selectedEntries: [(language: String, entry: EtymologyEntry, originalIndex: Int)] = []
        
        for (language, entries) in languageGroups {
            if entries.count == 1 {
                // Une seule entrée pour cette langue
                let originalIndex = chain.firstIndex { $0.language == language && $0.sourceWord == entries[0].sourceWord } ?? 0
                selectedEntries.append((language: language, entry: entries[0], originalIndex: originalIndex))
                print("✅ Langue '\(language)': une seule entrée gardée")
            } else {
                // Plusieurs entrées: garder la plus ancienne
                let oldestEntry = entries.min { entry1, entry2 in
                    return compareEntryDates(entry1, entry2)
                }!
                
                let originalIndex = chain.firstIndex { $0.language == language && $0.sourceWord == oldestEntry.sourceWord } ?? 0
                selectedEntries.append((language: language, entry: oldestEntry, originalIndex: originalIndex))
                
                print("🎯 Langue '\(language)': garde '\(oldestEntry.sourceWord) (\(oldestEntry.period ?? "?"))' (plus ancien)")
                
                // Afficher les entrées rejetées
                for rejectedEntry in entries where rejectedEntry.sourceWord != oldestEntry.sourceWord {
                    print("🔄 Rejeté: '\(rejectedEntry.language):\(rejectedEntry.sourceWord) (\(rejectedEntry.period ?? "?"))' (plus récent)")
                }
            }
        }
        
        // Reconstituer la chaîne dans l'ordre chronologique original
        let deduplicatedChain = selectedEntries
            .sorted { $0.originalIndex < $1.originalIndex }
            .map { $0.entry }
        
        if deduplicatedChain.count < chain.count {
            print("🧹 Résultat déduplication intelligente : \(chain.count) → \(deduplicatedChain.count) entrées")
            print("🔗 Chaîne finale: \(deduplicatedChain.map { "\($0.language):\($0.sourceWord) (\($0.period ?? "?"))" }.joined(separator: " → "))")
        }
        
        return deduplicatedChain
    }
    
    // Fonction helper pour comparer les dates des entrées
    private func compareEntryDates(_ entry1: EtymologyEntry, _ entry2: EtymologyEntry) -> Bool {
        let date1 = extractYearFromPeriod(entry1.period)
        let date2 = extractYearFromPeriod(entry2.period)
        
        // Si on a les deux dates, comparer numériquement
        if let year1 = date1, let year2 = date2 {
            return year1 < year2  // Plus ancien = plus petit
        }
        
        // Si une seule date est disponible, préférer celle avec date
        if date1 != nil && date2 == nil {
            return true  // entry1 a une date, préférer
        }
        if date1 == nil && date2 != nil {
            return false // entry2 a une date, préférer
        }
        
        // Si aucune date, garder le premier dans l'ordre original
        return true
    }
    
    // Fonction helper pour extraire l'année d'une période
    private func extractYearFromPeriod(_ period: String?) -> Int? {
        guard let period = period else { return nil }
        
        // Extraire le premier nombre de 4 chiffres trouvé
        let regex = try! NSRegularExpression(pattern: "\\b(\\\\d{4})\\b")
        let range = NSRange(period.startIndex..<period.endIndex, in: period)
        
        if let match = regex.firstMatch(in: period, range: range) {
            let yearRange = Range(match.range(at: 1), in: period)!
            return Int(String(period[yearRange]))
        }
        
        return nil
    }
}

// Structure pour la réponse de curation
struct CurationResponse: Codable {
    let selected_words: [CurationWordData]
}

struct CurationWordData: Codable {
    let word: String
    let description: String
    let tags: [String]
} 