import Foundation

class GPT4Service {
    static let shared = GPT4Service()
    private lazy var openAIService = OpenAIService()
    private lazy var normalizer: (String) -> String = {
        { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }()
    
    private(set) var lastRawResponse: String?
    
    private init() {}
    
    func analyzeLanguage(_ language: String) async throws -> LanguageAnalysis {
        print("\n🤖 Analyse de la langue:", language)
        
        // Validation de base
        let normalizedLanguage = normalizer(language)
        guard !normalizedLanguage.isEmpty else {
            print("❌ Nom de langue vide")
            throw ServiceError.invalidInput
        }
        
        let prompt = EtymologyPrompts.languageAnalysis
            .replacingOccurrences(of: "{language}", with: normalizedLanguage)
        
        print("📝 Envoi du prompt pour analyse")
        let response = try await openAIService.sendMessage(prompt)
        print("✅ Réponse reçue (\(response.count) caractères)")
        
        guard let data = response.data(using: String.Encoding.utf8) else {
            print("❌ Impossible d'encoder la réponse en UTF-8")
            throw ServiceError.encodingError
        }
        
        do {
            let analysis = try JSONDecoder().decode(LanguageAnalysis.self, from: data)
            print("""
                  ✅ Analyse décodée avec succès:
                     Type: \(analysis.type)
                     Nom: \(analysis.name)
                     Ville: \(analysis.description)
                     Période: \(analysis.periodStart) - \(analysis.periodEnd)
                  """)
            return analysis
        } catch {
            print("❌ Erreur de décodage:", error)
            print("Réponse brute:", response)
            throw ServiceError.decodingError
        }
    }
    
    func analyzeNewLanguage(
        _ word: String,
        sourceText: String,
        preprocessingResult: PreprocessingResult,
        knownLanguages: [String]
    ) async throws -> LanguageAnalysis {
        print("\n🤖 Analyse d'une nouvelle langue pour le mot '\(word)'")
        
        // Validation des entrées
        guard !word.isEmpty, !sourceText.isEmpty else {
            print("❌ Paramètres invalides")
            throw ServiceError.invalidInput
        }
        
        // Construction du prompt avec validation
        let prompt = try buildNewLanguagePrompt(
            word: word,
            sourceText: sourceText,
            preprocessingResult: preprocessingResult,
            knownLanguages: knownLanguages
        )
        
        print("📝 Envoi du prompt pour analyse")
        let response = try await openAIService.analyzeWithGPT4(prompt)
        print("✅ Réponse reçue (\(response.count) caractères)")
        
        guard let jsonData = response.data(using: .utf8) else {
            print("❌ Impossible d'encoder la réponse en UTF-8")
            throw ServiceError.parsingError
        }
        
        do {
            let analysis = try JSONDecoder().decode(LanguageAnalysis.self, from: jsonData)
            print("✅ Analyse décodée avec succès")
            return analysis
        } catch {
            print("❌ Erreur de décodage:", error)
            print("Réponse brute:", response)
            throw ServiceError.decodingError
        }
    }
    
    private func buildNewLanguagePrompt(word: String, sourceText: String, preprocessingResult: PreprocessingResult, knownLanguages: [String]) throws -> String {
        var prompt = EtymologyPrompts.newLanguageAnalysis
        
        // Validation et nettoyage des valeurs
        let sourceWords = preprocessingResult.etymology.sourceWords
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        
        guard !sourceWords.isEmpty else {
            print("❌ Aucun mot source valide")
            throw ServiceError.invalidInput
        }
        
        // Construction du prompt
        prompt = prompt.replacingOccurrences(of: "{word}", with: word)
        prompt = prompt.replacingOccurrences(of: "{source_word}", with: sourceWords)
        prompt = prompt.replacingOccurrences(of: "{source_text}", with: sourceText)
        prompt = prompt.replacingOccurrences(of: "{first_attestation}", with: preprocessingResult.etymology.firstAttestation ?? "Date inconnue")
        prompt = prompt.replacingOccurrences(of: "{etymology_chain}", with: preprocessingResult.etymology.etymologyChain)
        prompt = prompt.replacingOccurrences(of: "{known_languages}", with: knownLanguages.joined(separator: "\n"))
        
        return prompt
    }
    
    func analyzeHistoricalLanguages(_ prompt: String) async throws -> [HistoricalLanguage] {
        let response = try await openAIService.analyzeWithGPT4(prompt)
        
        // Extraire les requêtes SQL du texte
        let sqlStatements = response.components(separatedBy: "VALUES")
            .dropFirst()
            .map { statement -> String in
                guard let endIndex = statement.firstIndex(of: ";") else { return "" }
                return String(statement[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        
        // Parser chaque requête SQL en HistoricalLanguage
        return try sqlStatements.map { sqlValues -> HistoricalLanguage in
            let values = sqlValues.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            
            guard values.count >= 6 else {
                throw ServiceError.parsingError
            }
            
            let language = values[0].trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            let latitude = Double(values[1]) ?? 0
            let longitude = Double(values[2]) ?? 0
            let city = values[3].trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            let periodStart = values[4].trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            let periodEnd = values[5].trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            
            return HistoricalLanguage(
                language: language,
                city: city,
                latitude: latitude,
                longitude: longitude,
                period: "\(periodStart) - \(periodEnd)",
                justification: "Basé sur les sources historiques"
            )
        }
    }
    
    func analyzeEtymology(_ etymologyText: String, knownLanguages: [String]) async throws -> GPTEtymologyResponse {
        let prompt = EtymologyPrompts.etymologyAnalysis
            .replacingOccurrences(of: "{etymology_text}", with: etymologyText)
            .replacingOccurrences(of: "{known_languages}", with: knownLanguages.joined(separator: ", "))
        
        print("\n🤖 Envoi du message à OpenAI")
        print("📝 Longueur du message:", prompt.count)
        
        let response = try await openAIService.sendMessage(prompt)
        print("✅ Réponse reçue (\(response.count) caractères)")
        self.lastRawResponse = response
        print("\n📝 Réponse brute:")
        print(response)
        print("\n")
        
        return try parseResponse(response)
    }
    
    func parseResponse(_ response: String) throws -> GPTEtymologyResponse {
        guard let jsonData = response.data(using: .utf8) else {
            throw ServiceError.encodingError
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(GPTEtymologyResponse.self, from: jsonData)
    }
    
    func generateSQLQueries(_ etymology: String) async throws -> [String] {
        let prompt = EtymologyPrompts.etymologyAnalysis + "\n" + etymology
        let response = try await openAIService.sendMessage(prompt)
        
        _ = try parseResponse(response)
        return []
    }
}
