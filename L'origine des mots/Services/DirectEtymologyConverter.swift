import Foundation

class DirectEtymologyConverter {
    static let shared = DirectEtymologyConverter()
    
    private lazy var gptService = GPT4Service.shared
    
    private init() {}
    
    func convert(from response: String) async throws -> DirectEtymology {
        let data = Data(response.utf8)
        let gptResponse = try JSONDecoder().decode(GPTEtymologyResponse.self, from: data)
        return gptResponse.etymology
    }
    
    func convertToEtymology(word: String, preprocessed: PreprocessedEtymology) -> DirectEtymology {
        print("\n🔄 Conversion de l'étymologie pour '\(word)'")
        
        let languages = preprocessed.etymologyChain
            .components(separatedBy: "→")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        let sourceWords = preprocessed.sourceWords
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        let entries = zip(languages, sourceWords).map { language, sourceWord in
            EtymologyEntry(
                sourceWord: sourceWord,
                language: language,
                period: language == languages.last ? preprocessed.firstAttestation : nil
            )
        }
        
        return DirectEtymology(chain: entries)
    }
    
    static func convert(_ etymology: DirectEtymology) async throws -> [LanguageLocation] {
        print("\n🗺 Conversion de l'étymologie en locations...")
        var locations: [LanguageLocation] = []
        var missingLanguages: [String] = []
        
        // Lazy loading des langues uniquement quand nécessaire
        for entry in etymology.chain {
            print("  • Langue: \(entry.language)")
            if let location = try await SupabaseService.shared.getLocation(for: entry.language) {
                locations.append(location)
            } else {
                // Essayer d'ajouter une localisation par défaut pour les langues modernes courantes
                if let defaultLocation = getDefaultLocationFor(language: entry.language) {
                    print("  📍 Utilisation de la localisation par défaut pour: \(entry.language)")
                    locations.append(defaultLocation)
                } else {
                    missingLanguages.append(entry.language)
                    print("  ❌ Aucune localisation trouvée pour: \(entry.language)")
                }
            }
        }
        
        if !missingLanguages.isEmpty {
            print("⚠️ Langues sans localisation: \(missingLanguages.joined(separator: ", "))")
        }
        
        print("✅ \(locations.count) locations trouvées sur \(etymology.chain.count) langues")
        return locations
    }
    
    // Localisation par défaut pour les langues modernes courantes
    private static func getDefaultLocationFor(language: String) -> LanguageLocation? {
        let defaultLocations: [String: (lat: Double, lon: Double, description: String)] = [
            "Français": (48.8566, 2.3522, "Paris, France"),
            "French": (48.8566, 2.3522, "Paris, France"),
            "Anglais": (51.5074, -0.1278, "Londres, Royaume-Uni"),
            "English": (51.5074, -0.1278, "Londres, Royaume-Uni"),
            "Allemand": (52.5200, 13.4050, "Berlin, Allemagne"),
            "German": (52.5200, 13.4050, "Berlin, Allemagne"),
            "Espagnol": (40.4168, -3.7038, "Madrid, Espagne"),
            "Spanish": (40.4168, -3.7038, "Madrid, Espagne"),
            "Italien": (41.9028, 12.4964, "Rome, Italie"),
            "Italian": (41.9028, 12.4964, "Rome, Italie"),
            "Portugais": (38.7223, -9.1393, "Lisbonne, Portugal"),
            "Portuguese": (38.7223, -9.1393, "Lisbonne, Portugal"),
            "Russe": (55.7558, 37.6176, "Moscou, Russie"),
            "Russian": (55.7558, 37.6176, "Moscou, Russie"),
            "Chinois": (39.9042, 116.4074, "Pékin, Chine"),
            "Chinese": (39.9042, 116.4074, "Pékin, Chine"),
            "Japonais": (35.6762, 139.6503, "Tokyo, Japon"),
            "Japanese": (35.6762, 139.6503, "Tokyo, Japon"),
            "Néerlandais": (52.3676, 4.9041, "Amsterdam, Pays-Bas"),
            "Dutch": (52.3676, 4.9041, "Amsterdam, Pays-Bas")
        ]
        
        if let coords = defaultLocations[language] {
            return LanguageLocation(
                id: UUID(),
                language: language,
                latitude: coords.lat,
                longitude: coords.lon,
                city: coords.description,
                period: nil,
                abbreviations: nil,
                description: nil
            )
        }
        
        return nil
    }
} 