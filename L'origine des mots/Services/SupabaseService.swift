import Foundation
import CoreLocation

@globalActor actor SupabaseActor {
    static let shared = SupabaseActor()
}

@SupabaseActor
class SupabaseService: @unchecked Sendable {
    // Vrai singleton lazy
    private static var _shared: SupabaseService?
    static var shared: SupabaseService {
        if _shared == nil {
            _shared = SupabaseService()
        }
        return _shared!
    }
    
    // Session lazy
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = true
        config.requestCachePolicy = .returnCacheDataElseLoad
        
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "apikey": self.apiKey,
            "Authorization": "Bearer \(self.apiKey)"
        ]
        
        if #available(iOS 18.0, *) {
            config.allowsConstrainedNetworkAccess = true
            config.allowsExpensiveNetworkAccess = true
            #if os(iOS)
            config.multipathServiceType = .handover
            #endif
            config.urlCache = URLCache(
                memoryCapacity: 5_000_000,  // 5MB
                diskCapacity: 25_000_000,   // 25MB
                diskPath: "supabase_cache_v1"
            )
        } else {
            config.urlCache = URLCache(
                memoryCapacity: 2_500_000,  // 2.5MB
                diskCapacity: 10_000_000,   // 10MB
                diskPath: "supabase_cache_v1"
            )
        }
        
        return URLSession(configuration: config, delegate: CustomURLSessionDelegate(), delegateQueue: nil)
    }()
    
    private let baseURL = URL(string: "https://zwgycindbchpgiacsxac.supabase.co/rest/v1")!
    private let apiKey: String
    private var languageLocationsCache: [LanguageLocation]?
    // Cache temporaire pour les mots
    private var temporaryWordCache: [String: Word] = [:]
    private var cacheTimestamps: [String: Date] = [:] // Horodatage pour nettoyage du cache
    
    // Clés pour UserDefaults (cache persistant optionnel)
    private let cacheKey = "temporary_word_cache"
    private let timestampsKey = "cache_timestamps"
    private let queue = DispatchQueue(label: "com.originedemots.network", qos: .userInitiated)
    private let cacheValidityDuration: TimeInterval = 900 // 15 minutes
    
    // Décodeur unifié et robuste pour toutes les opérations Supabase
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        // Formatter principal robuste pour les dates Supabase avec microsecondes
        let primaryFormatter = DateFormatter()
        primaryFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        primaryFormatter.calendar = Calendar(identifier: .iso8601)
        primaryFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        primaryFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        // Formatter de fallback pour autres formats possibles
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"  // Sans microsecondes
        fallbackFormatter.calendar = Calendar(identifier: .iso8601)
        fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        // Stratégie custom qui essaie les deux formats
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Essayer le format principal avec microsecondes
            if let date = primaryFormatter.date(from: dateString) {
                return date
            }
            
            // Fallback vers le format sans microsecondes
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }
            
            // Si aucun format ne fonctionne, essayer ISO8601DateFormatter
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                    debugDescription: "Date string '\(dateString)' ne correspond à aucun format connu")
            )
        }
        
        return decoder
    }()
    
    // Décodeur spécialisé pour RemarkableWord (sans convertFromSnakeCase pour respecter les CodingKeys personnalisées)
    private let remarkableWordDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // PAS de convertFromSnakeCase car RemarkableWord a ses propres CodingKeys
        
        // Même stratégie de date robuste que le décodeur principal
        let primaryFormatter = DateFormatter()
        primaryFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        primaryFormatter.calendar = Calendar(identifier: .iso8601)
        primaryFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        primaryFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        fallbackFormatter.calendar = Calendar(identifier: .iso8601)
        fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = primaryFormatter.date(from: dateString) {
                return date
            }
            
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }
            
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                    debugDescription: "Date string '\(dateString)' ne correspond à aucun format connu")
            )
        }
        
        return decoder
    }()
    
    private init() {
        self.apiKey = Configuration.supabaseKey
        // Charger le cache persistant si disponible
        loadPersistentCache()
    }
    
    // Fonction utilitaire pour nettoyer les mots de façon cohérente
    private func cleanWord(_ word: String) -> String {
        return word.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
    
    func preloadLanguageLocations() async {
        Task(priority: .utility) {  // Priorité la plus basse
            print("🌍 Préchargement des locations en arrière-plan...")
            do {
                languageLocationsCache = try await fetchLanguageLocations()
                print("✅ Préchargement terminé")
            } catch {
                print("❌ Erreur de préchargement:", error)
                languageLocationsCache = nil
            }
        }
    }
    
    func fetchLanguageNames() async throws -> [String] {
        print("\n📚 Récupération des noms de langues")
        
        let url = baseURL.appendingPathComponent("language_locations")
            .appendingQueryItem("select", value: "language")
        
        let request = URLRequest(url: url)
        
        struct LanguageResponse: Codable {
            let language: String
        }
        
        let languages: [LanguageResponse] = try await performRequest(request)
        print("✅ \(languages.count) langues trouvées")
        return languages.map { $0.language }
    }
    
    func testConnection() async throws {
        print("\n🔌 Test de connexion à Supabase")
        
        // Test 1: Vérifier l'accès à language_locations
        print("🔍 Test 1: Accès à language_locations")
        let languageRequest = URLRequest(url: baseURL.appendingPathComponent("language_locations"))
        let _: [LanguageLocation] = try await performRequest(languageRequest)
        print("✅ language_locations accessible")
        
        // Test 2: Vérifier l'accès à la table etymologies avec champs explicites
        print("🔍 Test 2: Accès basique à la table etymologies")
        let etymologiesUrl = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology,created_at,short_description")
            .appendingQueryItem("limit", value: "1")
        print("🔍 URL de test etymologies: \(etymologiesUrl)")
        
        let etymologiesRequest = URLRequest(url: etymologiesUrl)
        let testSupabaseWords: [SupabaseWord] = try await performRequest(etymologiesRequest, decoder: remarkableWordDecoder)
        print("✅ Table etymologies accessible - \(testSupabaseWords.count) mot(s) trouvé(s)")
        
        // Test 3: Vérifier l'accès à la table remarkable_words
        print("🔍 Test 3: Test d'accès à la table remarkable_words")
        let remarkableUrl = baseURL.appendingPathComponent("remarkable_words")
            .appendingQueryItem("select", value: "id,word,tags,why_remarkable,created_at")
            .appendingQueryItem("limit", value: "1")
        print("🔍 URL de test remarkable_words: \(remarkableUrl)")
        
        let remarkableRequest = URLRequest(url: remarkableUrl)
        let testRemarkable: [RemarkableWord] = try await performRequest(remarkableRequest, decoder: remarkableWordDecoder)
        print("✅ Table remarkable_words accessible - \(testRemarkable.count) mot(s) remarquable(s) trouvé(s)")
        
        print("✅ Tous les tests de connexion réussis")
    }
    
    private func loadPersistentCache() {
        // Charger les timestamps
        if let timestampsData = UserDefaults.standard.data(forKey: timestampsKey),
           let decodedTimestamps = try? JSONDecoder().decode([String: Date].self, from: timestampsData) {
            cacheTimestamps = decodedTimestamps
        }
        
        // Nettoyer les caches expirés avant de charger
        let now = Date()
        let expiredKeys = cacheTimestamps.compactMap { key, timestamp in
            now.timeIntervalSince(timestamp) > 600 ? key : nil // 10 minutes
        }
        for key in expiredKeys {
            cacheTimestamps.removeValue(forKey: key)
        }
        
        print("🗃️ Cache persistant chargé avec \(cacheTimestamps.count) entrées valides")
    }
    
    private func performRequest<T: Decodable>(_ request: URLRequest, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200, 201:
            // Si la réponse est vide et qu'on attend EmptyResponse, retourner une instance vide
            if data.isEmpty && T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            
            // Si la réponse est vide mais qu'on n'attend pas EmptyResponse, c'est une erreur
            if data.isEmpty {
                print("⚠️ Réponse vide de Supabase pour une requête qui devrait retourner des données")
                throw ServiceError.noData
            }
            
            return try decoder.decode(T.self, from: data)
        case 204:
            // Statut 204 (No Content) - succès mais pas de contenu retourné
            // C'est normal pour les PATCH avec return=minimal
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            } else {
                print("⚠️ Statut 204 reçu mais type de retour attendu: \(T.self)")
                throw ServiceError.noData
            }
        case 401, 403:
            throw ServiceError.notAuthorized
        case 404:
            throw ServiceError.resourceNotFound
        default:
            print("❌ Erreur HTTP \(httpResponse.statusCode)")
            if !data.isEmpty {
                print("📄 Contenu de la réponse:", String(data: data, encoding: .utf8) ?? "Non décodable")
            }
            throw ServiceError.httpError(httpResponse.statusCode)
        }
    }
    
    // Ajout des méthodes minimum requises
    func fetchLanguageLocations() async throws -> [LanguageLocation] {
        if let cached = languageLocationsCache {
            print("📦 Utilisation du cache des langues (\(cached.count) langues)")
            return cached
        }
        
        print("🌍 Chargement des langues depuis Supabase...")
        
        // Ajout d'un tri et d'une limite plus élevée pour s'assurer de récupérer toutes les langues
        let url = baseURL.appendingPathComponent("language_locations")
            .appendingQueryItem("order", value: "created_at.desc")
            .appendingQueryItem("limit", value: "2000")  // Limite plus élevée pour être sûr
        
        print("🔍 URL de chargement: \(url)")
        let request = URLRequest(url: url)
        
        let locations: [LanguageLocation] = try await performRequest(request, decoder: decoder)
        print("✅ \(locations.count) langues chargées depuis Supabase")
        
        // Debug spécifique pour "Arabe maghrébin"
        let arabicLanguages = locations.filter { $0.language.lowercased().contains("arabe") }
        print("🔍 Debug - Langues arabes trouvées (\(arabicLanguages.count)):")
        for lang in arabicLanguages {
            print("   - \"\(lang.language)\" (ID: \(lang.id))")
            // Vérification byte par byte pour "Arabe maghrébin"
            if lang.language == "Arabe maghrébin" {
                let bytes = Array(lang.language.utf8)
                print("   ✅ TROUVÉ Arabe maghrébin! Bytes: \(bytes)")
            }
        }
        
        // Vérification si "Arabe maghrébin" est présent
        let arabemaghrebinFound = locations.contains { $0.language == "Arabe maghrébin" }
        print("🔍 'Arabe maghrébin' trouvé dans les résultats: \(arabemaghrebinFound)")
        
        if !arabemaghrebinFound {
            print("⚠️ 'Arabe maghrébin' manquant! Vérification des langues contenant 'maghrébin':")
            let maghrebinVariants = locations.filter { $0.language.lowercased().contains("maghrébin") || $0.language.lowercased().contains("maghrebin") }
            for variant in maghrebinVariants {
                print("   - Trouvé: \"\(variant.language)\" (ID: \(variant.id))")
            }
        }
        
        languageLocationsCache = locations
        return locations
    }
    
    // Méthode pour récupérer la localisation d'une langue spécifique
    func getLocation(for language: String) async throws -> LanguageLocation? {
        print("🔍 Recherche de la localisation pour la langue: \(language)")
        
        // D'abord vérifier dans le cache
        if let cached = languageLocationsCache {
            if let location = cached.first(where: { compareIgnoringAccents($0.language, language) }) {
                print("✅ Localisation trouvée dans le cache pour: \(language)")
                return location
            }
        }
        
        // Si pas dans le cache, faire une requête spécifique
        let url = baseURL.appendingPathComponent("language_locations")
            .appendingQueryItem("language", value: "ilike.\(language)")  // Utilisation de ilike pour une recherche insensible à la casse
        
        print("🔍 URL de recherche: \(url)")
        let request = URLRequest(url: url)
        
        let locations: [LanguageLocation] = try await performRequest(request, decoder: decoder)
        
        if let location = locations.first {
            print("✅ Localisation trouvée en base pour: \(language)")
        return location
        } else {
            print("⚠️ Aucune localisation trouvée pour: \(language)")
            return nil
        }
    }
    
    // Méthode pour marquer un mot comme remarquable
    func addRemarkableWord(_ remarkableWord: RemarkableWord, source: RemarkableSource = .automatic) async throws {
        print("🌟 Marquage du mot '\(remarkableWord.word)' comme remarquable (source: \(source))...")
        
        let url = baseURL.appendingPathComponent("remarkable_words")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        
        // Préparation du corps de la requête pour la table remarkable_words
        let newRemarkableWord: [String: Any] = [
            "id": remarkableWord.id.uuidString,
            "word": remarkableWord.word,
            "tags": remarkableWord.tags,
            "why_remarkable": remarkableWord.shortDescription ?? "Mot remarquable ajouté automatiquement",
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: newRemarkableWord)
        
        // Utiliser remarkableWordDecoder car RemarkableWord a ses propres CodingKeys
        let _: [RemarkableWord] = try await performRequest(request, decoder: remarkableWordDecoder)
        print("✅ Mot '\(remarkableWord.word)' marqué comme remarquable")
    }
    
    // Structure pour la sauvegarde en base (correspondant exactement aux colonnes de etymologies)
    private struct DatabaseWord: Codable {
        let id: String
        let word: String
        let etymology: [EtymologyEntry]
        let shortDescription: String?
        let distanceKm: Double?
        
        enum CodingKeys: String, CodingKey {
            case id, word, etymology
            case shortDescription = "short_description"
            case distanceKm = "distance_km"
        }
    }
    
    // Structure pour décoder les données de Supabase (format exact de la DB)
    private struct SupabaseWord: Codable {
        let id: String
        let word: String
        let etymology: [EtymologyEntry]  // Array direct dans Supabase
        let createdAt: Date?  // Optionnel car peut être manquant dans anciens enregistrements
        let shortDescription: String?
        let distanceKm: Double?  // Distance étymologique en kilomètres
        let isRemarkable: Bool?  // Statut de mot remarquable
        let isComposedWord: Bool?  // Si le mot est composé (ex: abat-jour)
        let components: [String]?  // Composants du mot composé (ex: ["abat", "jour"])
        
        enum CodingKeys: String, CodingKey {
            case id, word, etymology
            case createdAt = "created_at"
            case shortDescription = "short_description"
            case distanceKm = "distance_km"
            case isRemarkable = "is_remarkable"
            case isComposedWord = "is_composed_word"
            case components
        }
        
        // Custom init pour gérer le décodage de distance_km qui peut être string ou double
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            word = try container.decode(String.self, forKey: .word)
            etymology = try container.decode([EtymologyEntry].self, forKey: .etymology)
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
            isRemarkable = try container.decodeIfPresent(Bool.self, forKey: .isRemarkable)
            isComposedWord = try container.decodeIfPresent(Bool.self, forKey: .isComposedWord)
            components = try container.decodeIfPresent([String].self, forKey: .components)
            
            // 🔧 Décodage simple de distance_km
            distanceKm = try container.decodeIfPresent(Double.self, forKey: .distanceKm)
        }
        
        // Custom encode pour s'assurer que Codable utilise notre décodeur
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(word, forKey: .word)
            try container.encode(etymology, forKey: .etymology)
            try container.encodeIfPresent(createdAt, forKey: .createdAt)
            try container.encodeIfPresent(shortDescription, forKey: .shortDescription)
            try container.encodeIfPresent(distanceKm, forKey: .distanceKm)
            try container.encodeIfPresent(isRemarkable, forKey: .isRemarkable)
            try container.encodeIfPresent(isComposedWord, forKey: .isComposedWord)
            try container.encodeIfPresent(components, forKey: .components)
        }
        
        func toWord() -> Word {
        return Word(
                id: id,
            word: word,
                etymology: DirectEtymology(chain: etymology),
                language: "français",
                source: "database",
                createdAt: createdAt ?? Date(),
                updatedAt: createdAt ?? Date(),
                foundInCNRTL: true,
                foundWithCNRTLAndClaude: true,
                isRemarkable: isRemarkable ?? false,
                shortDescription: shortDescription,
                distanceKm: distanceKm,
                isComposedWord: isComposedWord ?? false,
                components: components ?? [],
                gptAnalysis: nil
            )
        }
    }
    
    // Méthode pour sauvegarder un mot avec son analyse étymologique (version corrigée)
    // Retourne la distance calculée pour feedback utilisateur
    func saveWordWithAnalysis(_ word: Word) async throws -> Double {
        print("💾 Sauvegarde du mot '\(word.word)' avec son analyse...")
        
        // Utiliser la nouvelle méthode avec calcul de distance
        return try await saveWordWithDistance(word)
    }
    
    // Méthode pour sauvegarder un mot simple (sans analyse spécifique)
    // Retourne la distance calculée pour feedback utilisateur  
    func saveWord(_ word: Word) async throws -> Double {
        print("💾 Sauvegarde du mot '\(word.word)'...")
        
        // Utiliser la nouvelle méthode avec calcul de distance
        return try await saveWordWithDistance(word)
    }
    
    // Méthode pour sauvegarder le cache persistant
    private func savePersistentCache() {
        do {
            let cacheData = try JSONEncoder().encode(temporaryWordCache)
            let timestampsData = try JSONEncoder().encode(cacheTimestamps)
            
            UserDefaults.standard.set(cacheData, forKey: cacheKey)
            UserDefaults.standard.set(timestampsData, forKey: timestampsKey)
            
            print("💾 Cache persistant sauvegardé (\(temporaryWordCache.count) mots)")
        } catch {
            print("❌ Erreur lors de la sauvegarde du cache:", error)
        }
    }
    
    // Méthode pour récupérer les mots remarquables (avec fallback vers remarkable_words)
    func fetchRemarkableWords(limit: Int = 200) async throws -> [RemarkableWord] {
        print("🌟 Récupération des \(limit) mots remarquables...")
        
        // Essayer d'abord avec la nouvelle approche (is_remarkable)
        do {
            // ✅ Nouvelle approche avec filtre direct sur etymologies
            let url = baseURL.appendingPathComponent("etymologies")
                .appendingQueryItem("select", value: "id,word,created_at,is_remarkable,short_description")
                .appendingQueryItem("is_remarkable", value: "eq.true")
                .appendingQueryItem("order", value: "created_at.desc")
                .appendingQueryItem("limit", value: "\(limit)")
            
            print("🔍 URL complète (nouvelle approche): \(url)")
            
            var request = URLRequest(url: url)
            // ✅ Forcer un rafraîchissement côté client
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            
            struct RemarkableWordResponse: Codable {
                let id: String
                let word: String
                let created_at: Date?
                let is_remarkable: Bool?
                let short_description: String?
            }
            
            let responses: [RemarkableWordResponse] = try await performRequest(request, decoder: remarkableWordDecoder)
            
            // ✅ Filtrer côté client pour s'assurer qu'on a bien les bons mots
            let filteredResponses = responses.filter { $0.is_remarkable == true }
            
            print("🔍 DEBUG: Réponses brutes reçues: \(responses.count)")
            print("🔍 DEBUG: Réponses filtrées (is_remarkable=true): \(filteredResponses.count)")
            print("🔍 DEBUG: Premiers 10 mots reçus:")
            for (index, response) in filteredResponses.prefix(10).enumerated() {
                print("   \(index + 1). \(response.word) (created_at: \(response.created_at?.description ?? "nil"), is_remarkable: \(response.is_remarkable ?? false))")
            }
            if filteredResponses.count > 10 {
                print("🔍 DEBUG: Derniers 5 mots reçus:")
                for (index, response) in filteredResponses.suffix(5).enumerated() {
                    let actualIndex = filteredResponses.count - 5 + index + 1
                    print("   \(actualIndex). \(response.word) (created_at: \(response.created_at?.description ?? "nil"), is_remarkable: \(response.is_remarkable ?? false))")
                }
            }
            
            let remarkableWords = filteredResponses.map { response in
                RemarkableWord(
                    id: UUID(uuidString: response.id) ?? UUID(),
                    word: response.word,
                    shortDescription: response.short_description,
                    tags: [],
                    createdAt: response.created_at ?? Date()
                )
            }
            
            print("✅ \(remarkableWords.count) mots remarquables récupérés (nouvelle approche)")
            print("🔍 DIAGNOSTIC: IDs remarquables home: \(remarkableWords.prefix(5).map { $0.word })")
            return remarkableWords
            
        } catch {
            print("⚠️ Nouvelle approche échouée, fallback vers remarkable_words...")
            print("   - Erreur: \(error)")
            
            // Fallback vers l'ancienne table remarkable_words
            let fallbackUrl = baseURL.appendingPathComponent("remarkable_words")
                .appendingQueryItem("order", value: "created_at.desc")
                .appendingQueryItem("limit", value: "\(limit)")
            
            print("🔍 URL fallback: \(fallbackUrl)")
            
            let fallbackRequest = URLRequest(url: fallbackUrl)
            
            do {
                // Utiliser remarkableWordDecoder car RemarkableWord a ses propres CodingKeys
                let remarkableWords: [RemarkableWord] = try await performRequest(fallbackRequest, decoder: remarkableWordDecoder)
                
                print("✅ \(remarkableWords.count) mots remarquables récupérés (fallback)")
                return remarkableWords
            } catch {
                print("❌ Erreur lors du fallback:")
                print("   - Type d'erreur: \(type(of: error))")
                print("   - Description: \(error)")
                print("⚠️ Conflit lors de la sauvegarde de '(newLanguage.name)' - langue probablement déjà créée")
            }
        }
        // Ajouté : retour vide si tout échoue
        return []
    }
    
    // Méthode pour récupérer un mot spécifique avec double vérification anti-conflit
    func fetchWord(_ wordText: String) async throws -> Word? {
        print("🔍 Recherche du mot '\(wordText)' en base...")
        
        // D'abord vérifier dans le cache temporaire
        let cleanedWord = cleanWord(wordText)
        if let cachedWord = temporaryWordCache[cleanedWord] {
            print("📦 Mot '\(wordText)' trouvé dans le cache temporaire")
            print("🔍 Debug cache: isComposedWord = \(cachedWord.isComposedWord)")
            print("🔍 Debug cache: components = \(cachedWord.components)")
            print("🔍 Debug cache: gptAnalysis présent = \(cachedWord.gptAnalysis != nil)")
            
            // TEMPORARY FIX: Vérifier si le cache a les nouveaux champs
            // Si le mot est marqué comme composé dans gptAnalysis mais pas dans les champs directs,
            // on invalide le cache pour forcer un rechargement
            if let analysis = cachedWord.gptAnalysis {
                let isComposedInAnalysis = analysis.is_composed_word ?? false
                let _ = !(analysis.components?.isEmpty ?? true)  // Éviter le warning unused
                
                if isComposedInAnalysis && !cachedWord.isComposedWord {
                    print("🔄 Cache obsolète détecté (champs composés manquants), rechargement...")
                    temporaryWordCache.removeValue(forKey: cleanedWord)
                    cacheTimestamps.removeValue(forKey: cleanedWord)
                    // Continue vers la requête base de données
                } else {
                    print("🔍 Debug cache: is_composed_word = \(analysis.is_composed_word ?? false)")
                    print("🔍 Debug cache: components = \(analysis.components?.joined(separator: ", ") ?? "aucun")")
                    return cachedWord
                }
            } else {
                // Pas d'analyse GPT, utiliser le cache tel quel
                return cachedWord
            }
        }
        
        // Double vérification : recherche exacte ET ilike pour éviter les conflits
        // 1. Vérification exacte d'abord (plus stricte)
        let exactUrl = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology,created_at,short_description,distance_km,is_remarkable,is_composed_word,components")
            .appendingQueryItem("word", value: "eq.\(wordText)")
            .appendingQueryItem("limit", value: "1")
        
        print("🔍 Vérification exacte: \(exactUrl)")
        var request = URLRequest(url: exactUrl)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData // Force refresh
        
        let (exactData, exactResponse) = try await session.data(for: request)
        if let httpResponse = exactResponse as? HTTPURLResponse, 
           httpResponse.statusCode == 200,
           let exactWords: [SupabaseWord] = try? remarkableWordDecoder.decode([SupabaseWord].self, from: exactData),
           !exactWords.isEmpty {
            print("✅ Correspondance EXACTE trouvée pour '\(wordText)'")
            let word = exactWords.first!.toWord()
            temporaryWordCache[cleanedWord] = word
            return word
        }
        
        // 2. Si pas de correspondance exacte, essayer ilike
        let ilikeUrl = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology,created_at,short_description,distance_km,is_remarkable,is_composed_word,components")
            .appendingQueryItem("word", value: "ilike.\(wordText)")
            .appendingQueryItem("limit", value: "1")
        
        print("🔍 Recherche ilike: \(ilikeUrl)")
        request = URLRequest(url: ilikeUrl)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData // Force refresh
        
        // 🔍 DEBUG: Logger la réponse brute de Supabase
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        
        print("🔍 DEBUG: Status HTTP: \(httpResponse.statusCode)")
        print("🔍 DEBUG: Réponse brute de Supabase pour '\(wordText)':")
        if let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ServiceError.httpError(httpResponse.statusCode)
        }
        
        let supabaseWords: [SupabaseWord] = try remarkableWordDecoder.decode([SupabaseWord].self, from: data)
        
        if let supabaseWord = supabaseWords.first {
            // Afficher les logs de distance seulement si > 0
            if let distance = supabaseWord.distanceKm, distance > 0 {
                print("🔍 DEBUG: SupabaseWord - distanceKm: \(distance)")
            }
            let word = supabaseWord.toWord()  // Conversion vers notre format interne
            if let distance = word.distanceKm, distance > 0 {
                print("🔍 DEBUG: Word après conversion - distanceKm: \(distance)")
            }
            print("✅ Mot '\(wordText)' trouvé en base de données")
            
            // Ajouter au cache temporaire
            temporaryWordCache[cleanedWord] = word
            cacheTimestamps[cleanedWord] = Date()
            
            return word
        }
        
        // Si recherche ilike échoue, essayer avec pattern matching en fallback
        print("🔄 Recherche ilike échouée, essai avec recherche pattern...")
        let fallbackUrl = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology,created_at,short_description,distance_km,is_remarkable,is_composed_word,components")
            .appendingQueryItem("word", value: "ilike.*\(wordText)*")
            .appendingQueryItem("limit", value: "1")
        
        print("🔍 URL fallback: \(fallbackUrl)")
        let fallbackRequest = URLRequest(url: fallbackUrl)
        let fallbackWords: [SupabaseWord] = try await performRequest(fallbackRequest, decoder: remarkableWordDecoder)
        
        if let supabaseWord = fallbackWords.first {
            let word = supabaseWord.toWord()
            
            // Vérifier que le mot trouvé correspond bien au mot recherché (éviter les duplications)
            if word.word.lowercased() == wordText.lowercased() {
                print("✅ Mot '\(wordText)' trouvé avec recherche approximative: '\(word.word)'")
                
                // Ajouter au cache temporaire
                temporaryWordCache[cleanedWord] = word
                cacheTimestamps[cleanedWord] = Date()
                
                return word
            } else {
                print("⚠️ Mot trouvé '\(word.word)' ne correspond pas au mot recherché '\(wordText)' - ignoré")
            }
        }
        
        print("⚠️ Mot '\(wordText)' non trouvé en base de données")
        
        // Ajouter un délai pour éviter les logs trop rapides
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconde
        
        return nil
    }
    
    // Fonction pour invalider le cache d'un mot et forcer un rechargement depuis la BDD
    func invalidateWordCache(_ wordText: String) async {
        let cleanedWord = cleanWord(wordText)
        temporaryWordCache.removeValue(forKey: cleanedWord)
        cacheTimestamps.removeValue(forKey: cleanedWord)
        print("🗑️ Cache invalidé pour le mot '\(wordText)'")
        
        // Attendre plus longtemps pour la réplication Supabase si le mot vient d'être créé
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 secondes
    }
    
    // Fonction pour vider complètement le cache
    func clearCache() {
        temporaryWordCache.removeAll()
        cacheTimestamps.removeAll()
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: timestampsKey)
        print("🗑️ Cache complètement vidé")
    }
    
    // Fonction pour vider le cache des mots remarquables et forcer un rechargement
    func clearRemarkableWordsCache() async {
        // Invalider toutes les entrées du cache qui sont marquées comme remarquables
        let remarkableWords = temporaryWordCache.filter { $0.value.isRemarkable }
        for (key, _) in remarkableWords {
            temporaryWordCache.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
        }
        print("🗑️ Cache des mots remarquables vidé (\(remarkableWords.count) entrées supprimées)")
    }
    
    // Fonction pour forcer le rechargement d'un mot depuis la BDD
    func fetchWordFromDatabase(_ wordText: String) async throws -> Word? {
        print("🔄 Rechargement forcé du mot '\(wordText)' depuis la BDD...")
        
        // Invalider le cache d'abord
        await invalidateWordCache(wordText)
        
        // Puis faire une nouvelle requête
        return try await fetchWord(wordText)
    }
    
    // Fonction pour rechercher un mot avec retry (utile après création)
    func fetchWordWithRetry(_ wordText: String, maxAttempts: Int = 3) async throws -> Word? {
        print("🔄 Recherche avec retry du mot '\(wordText)' (max \(maxAttempts) tentatives)...")
        
        for attempt in 1...maxAttempts {
            print("🔍 Tentative \(attempt)/\(maxAttempts) pour '\(wordText)'...")
            
            if let word = try await fetchWord(wordText) {
                print("✅ Mot '\(wordText)' trouvé à la tentative \(attempt)")
                return word
            }
            
            // Attendre plus longtemps entre les tentatives
            if attempt < maxAttempts {
                let delay = attempt * 500_000_000 // 0.5s, 1s, 1.5s...
                print("⏳ Attente de \(delay / 1_000_000_000)s avant la prochaine tentative...")
                try await Task.sleep(nanoseconds: UInt64(delay))
            }
        }
        
        print("❌ Mot '\(wordText)' non trouvé après \(maxAttempts) tentatives")
        return nil
    }
    
    // Méthode pour récupérer un mot par son ID
    func fetchWord(byId wordId: String) async throws -> Word? {
        print("🔍 Recherche du mot avec ID '\(wordId)' en base...")
        
        // Recherche par ID avec champs explicites
        let url = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology,created_at,short_description,distance_km,is_remarkable,is_composed_word,components")
            .appendingQueryItem("id", value: "eq.\(wordId)")
            .appendingQueryItem("limit", value: "1")
        
        print("🔍 URL de recherche par ID: \(url)")
        
        let request = URLRequest(url: url)
        let supabaseWords: [SupabaseWord] = try await performRequest(request, decoder: remarkableWordDecoder)
        
        if let supabaseWord = supabaseWords.first {
            let word = supabaseWord.toWord()  // Conversion vers notre format interne
            print("✅ Mot avec ID '\(wordId)' trouvé: '\(word.word)'")
            return word
        }
        
        print("⚠️ Mot avec ID '\(wordId)' non trouvé en base de données")
        return nil
    }
    
    // MARK: - Distance Calculations
    
    /// Calcule le total des kilomètres parcourus par tous les mots de l'app
    /// Utilise la colonne distance_km qui contient la distance numérique
    func getTotalKilometers() async throws -> Double {
        print("🔍 Calcul du total des kilomètres...")
        
        // Test de requête simple d'abord
        let testUrl = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "word,distance_km")
            .appendingQueryItem("limit", value: "3")
        
        print("🔍 URL de test: \(testUrl)")
        
        let testRequest = URLRequest(url: testUrl)
        
        struct WordDistanceTest: Codable {
            let word: String
            let distance_km: Double?
            
            enum CodingKeys: String, CodingKey {
                case word, distance_km
            }
        }
        
        let testWords: [WordDistanceTest] = try await performRequest(testRequest, decoder: remarkableWordDecoder)
        
        print("🧪 Test de décodage (3 premiers mots):")
        for testWord in testWords {
            print("   - '\(testWord.word)': distance_km = \(testWord.distance_km?.description ?? "nil")")
        }
        
        // Récupérer tous les mots avec leur distance_km
        let url = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "word,distance_km")
        
        let request = URLRequest(url: url)
        
        struct WordDistance: Codable {
            let word: String
            let distance_km: Double?
            
            enum CodingKeys: String, CodingKey {
                case word, distance_km
            }
        }
        
        let words: [WordDistance] = try await performRequest(request, decoder: remarkableWordDecoder)
        print("📊 Nombre total de mots en base : \(words.count)")
        
        // Compter les mots avec et sans distance (inclure distance = 0)
        let wordsWithDistance = words.filter { $0.distance_km != nil }
        let wordsWithoutDistance = words.filter { $0.distance_km == nil }
        
        print("📊 Mots avec distance : \(wordsWithDistance.count)")
        print("📊 Mots sans distance : \(wordsWithoutDistance.count)")
        
        // Debug: afficher quelques exemples
        for (index, word) in wordsWithDistance.prefix(5).enumerated() {
            print("📊 Exemple \(index + 1): '\(word.word)' -> \(word.distance_km ?? 0) km")
        }
        
        // Calculer la somme des distances (inclure 0 pour totaliser correctement)
        let distances: [Double] = words.compactMap { word in
            guard let distance = word.distance_km else { return nil }
            return distance
        }
        
        print("📊 Distances valides trouvées : \(distances.count)")
        print("📊 Premières distances : \(Array(distances.prefix(10)))")
        let total = distances.reduce(0, +)
        
        print("📊 Total calculé : \(total) km")
        
        // 🚨 Si le total est 0 mais qu'il y a des mots, diagnostic détaillé
        if total == 0 && words.count > 0 {
            print("🚨 PROBLÈME DÉTECTÉ : Total=0 mais \(words.count) mots en base")
            
            // Afficher les premiers mots et leurs valeurs exactes
            for (index, word) in words.prefix(10).enumerated() {
                print("🚨 Mot \(index + 1): '\(word.word)' distance_km=\(word.distance_km?.description ?? "nil")")
            }
            
            // Rechercher spécifiquement le mot "cannibale" mentionné par l'utilisateur
            if let cannibalWord = words.first(where: { $0.word == "cannibale" }) {
                print("🚨 Mot 'cannibale' trouvé: distance_km=\(cannibalWord.distance_km?.description ?? "nil")")
            } else {
                print("🚨 Mot 'cannibale' NON trouvé dans la liste")
            }
            
            // Tester avec une requête SQL directe potentielle
            print("🚨 SUGGESTION: Vérifier que la colonne distance_km existe bien et n'est pas NULL")
            print("🚨 SUGGESTION: SELECT word, distance_km FROM etymologies WHERE distance_km IS NOT NULL LIMIT 5;")
        }
        
        return total
    }
    
    /// 🔧 Méthode de diagnostic pour debug les kilomètres
    func diagnosticKilometers() async throws -> String {
        print("🔬 === DIAGNOSTIC COMPLET KILOMÈTRES ===")
        
        // Test avec une requête ultra-simple
        let simpleUrl = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "word")
            .appendingQueryItem("limit", value: "5")
        
        let simpleRequest = URLRequest(url: simpleUrl)
        let simpleWords: [[String: String]] = try await performRequest(simpleRequest, decoder: decoder)
        print("🔬 Test simple OK: \(simpleWords.count) mots trouvés")
        
        // Test avec distance_km
        let distanceUrl = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "word,distance_km")
            .appendingQueryItem("limit", value: "10")
        
        let distanceRequest = URLRequest(url: distanceUrl)
        
        struct DistanceTest: Codable {
            let word: String
            let distance_km: Double?
        }
        
        let distanceWords: [DistanceTest] = try await performRequest(distanceRequest, decoder: decoder)
        print("🔬 Test distance OK: \(distanceWords.count) mots avec colonne distance_km")
        
        var diagnosis = "=== DIAGNOSTIC ===\n"
        diagnosis += "Mots en base: \(simpleWords.count)+\n"
        diagnosis += "Colonnes accessibles: word, distance_km\n"
        diagnosis += "Premiers mots:\n"
        
        for (index, word) in distanceWords.enumerated() {
            let wordName = word.word
            let distance = word.distance_km
            diagnosis += "\(index + 1). \(wordName): \(distance?.description ?? "nil")\n"
        }
        
        print("🔬 === FIN DIAGNOSTIC ===")
        return diagnosis
    }
    
    /// 🔧 Force une synchronisation complète des distances (migration manuelle)
    func forceSyncAllDistances() async throws -> Int {
        print("🔄 === SYNCHRONISATION FORCÉE DES DISTANCES ===")
        
        // Étape 1: Récupérer tous les mots avec leur étymologie
        let url = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology,distance_km")
        
        let request = URLRequest(url: url)
        
        struct WordWithEtymology: Codable {
            let id: String
            let word: String
            let etymology: [EtymologyEntry]
            let distance_km: Double?
            
            // Custom decoder pour gérer distance_km
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                word = try container.decode(String.self, forKey: .word)
                etymology = try container.decode([EtymologyEntry].self, forKey: .etymology)
                
                // Essayer string puis double pour distance_km
                if let distanceString = try container.decodeIfPresent(String.self, forKey: .distance_km) {
                    distance_km = Double(distanceString)
                } else {
                    distance_km = try container.decodeIfPresent(Double.self, forKey: .distance_km)
                }
            }
            
            enum CodingKeys: String, CodingKey {
                case id, word, etymology, distance_km
            }
        }
        
        let allWords: [WordWithEtymology] = try await performRequest(request, decoder: decoder)
        print("📊 Total des mots en base: \(allWords.count)")
        
        // Étape 2: Identifier les mots sans distance ou avec distance = 0
        let wordsToUpdate = allWords.filter { word in
            guard let distance = word.distance_km else { return true }
            return distance <= 0.0
        }
        
        print("📊 Mots nécessitant une mise à jour: \(wordsToUpdate.count)")
        
        // Étape 3: Recalculer et mettre à jour chaque mot
        var updatedCount = 0
        
        for (index, wordData) in wordsToUpdate.enumerated() {
            print("🔄 (\(index + 1)/\(wordsToUpdate.count)) Traitement de '\(wordData.word)'...")
            
            do {
                // Créer un objet Word temporaire
                let tempWord = Word(
                    id: wordData.id,
                    word: wordData.word,
                    etymology: DirectEtymology(chain: wordData.etymology),
                    language: "français",
                    source: "CNRTL",
                    createdAt: Date(),
                    updatedAt: Date(),
                    foundInCNRTL: true,
                    foundWithCNRTLAndClaude: true,
                    isRemarkable: false,
                    shortDescription: nil,
                    distanceKm: nil,
                    isComposedWord: false,
                    components: [],
                    gptAnalysis: nil
                )
                
                // Calculer la distance
                let distance = try await tempWord.calculateEtymologicalDistance()
                
                // Mettre à jour en base
                let updateUrl = baseURL.appendingPathComponent("etymologies")
                    .appendingQueryItem("id", value: "eq.\(wordData.id)")
                
                var updateRequest = URLRequest(url: updateUrl)
                updateRequest.httpMethod = "PATCH"
                updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                updateRequest.setValue("return=minimal", forHTTPHeaderField: "Prefer")
                
                let updateData: [String: Any] = [
                    "distance_km": distance
                ]
                updateRequest.httpBody = try JSONSerialization.data(withJSONObject: updateData)
                
                let _: EmptyResponse = try await performRequest(updateRequest, decoder: decoder)
                updatedCount += 1
                
                print("✅ '\(wordData.word)': \(String(format: "%.1f", distance)) km")
                
            } catch {
                print("❌ Erreur pour '\(wordData.word)': \(error)")
            }
            
            // Pause courte pour éviter la surcharge
            if index % 10 == 9 {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconde
            }
        }
        
        print("🎉 === SYNCHRONISATION TERMINÉE ===")
        print("✅ \(updatedCount)/\(wordsToUpdate.count) mots mis à jour")
        
        return updatedCount
    }
    
    /// Sauvegarde un mot avec calcul automatique de la distance
    /// Retourne la distance calculée pour feedback utilisateur
    func saveWordWithDistance(_ word: Word) async throws -> Double {
        // Calculer la distance du parcours étymologique
        let distance = try await word.calculateEtymologicalDistance()
        
        // Créer une version du mot avec la distance stockée dans shortDescription
        let wordWithDistance = Word(
            id: word.id,
            word: word.word,
            etymology: word.etymology,
            language: word.language,
            source: word.source,
            createdAt: word.createdAt,
            updatedAt: word.updatedAt,
            foundInCNRTL: word.foundInCNRTL,
            foundWithCNRTLAndClaude: word.foundWithCNRTLAndClaude,
            isRemarkable: word.isRemarkable,
            shortDescription: String(distance),
            distanceKm: distance,
            isComposedWord: word.isComposedWord,
            components: word.components,
            gptAnalysis: word.gptAnalysis
        )
        
        // Vérifier d'abord si le mot existe déjà pour éviter l'erreur 409
        print("🔍 Vérification si le mot '\(word.word)' existe déjà...")
        print("🔍 Mot original: '\(word.word)'")
        print("🔍 Mot nettoyé pour cache: '\(cleanWord(word.word))'")
        
        // Essayer d'abord avec une requête directe pour forcer le bypass du cache
        let directSearchUrl = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,distance_km")
            .appendingQueryItem("word", value: "eq.\(word.word)")
            .appendingQueryItem("limit", value: "1")
        
        print("🔍 Recherche directe avec URL: \(directSearchUrl)")
        
        let directRequest = URLRequest(url: directSearchUrl)
        
        struct ExistingWordResult: Codable {
            let id: String
            let word: String
            let distance_km: Double?
        }
        
        let directResults: [ExistingWordResult] = try await performRequest(directRequest, decoder: decoder)
        
        if !directResults.isEmpty {
            let existingWord = directResults.first!
            print("⚠️ DÉTECTION: Le mot '\(word.word)' existe déjà en base avec ID: \(existingWord.id)")
            print("🔍 Distance actuelle: \(existingWord.distance_km?.description ?? "nil") km")
            
            // Vérifier si une mise à jour est nécessaire
            let shouldUpdate = existingWord.distance_km == nil || existingWord.distance_km == 0.0
            
            if shouldUpdate {
                print("🔄 Mise à jour nécessaire car distance manquante ou nulle")
            } else {
                print("ℹ️ Distance déjà présente (\(existingWord.distance_km!.description) km), mise à jour forcée pour nouvelle étymologie")
            }
        } else {
            print("✅ Recherche directe: Le mot '\(word.word)' n'existe pas en base")
        }
        
        // Utiliser la recherche directe comme source de vérité au lieu du cache
        if !directResults.isEmpty {
            let existingWord = directResults.first!
            print("⚠️ Le mot '\(word.word)' existe déjà - mise à jour au lieu de création")
            
            // Utiliser PATCH pour mettre à jour avec le VRAI ID du mot existant
            let updateUrl = baseURL.appendingPathComponent("etymologies")
                .appendingQueryItem("id", value: "eq.\(existingWord.id)")
            
            var updateRequest = URLRequest(url: updateUrl)
            updateRequest.httpMethod = "PATCH"
            updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            updateRequest.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            
            // Mettre à jour l'étymologie ET la distance (même si elle existe déjà)
            let updateData: [String: Any] = [
                "etymology": wordWithDistance.etymology.chain.map { entry in
                [
                    "sourceWord": entry.sourceWord,
                    "language": entry.language,
                    "period": entry.period as Any,
                    "originalScript": entry.originalScript as Any,
                    "translation": entry.translation as Any
                ]
            },
                "distance_km": distance
            ]
            updateRequest.httpBody = try JSONSerialization.data(withJSONObject: updateData)
            
            let _: EmptyResponse = try await performRequest(updateRequest, decoder: decoder)
            print("✅ Mot '\(word.word)' mis à jour avec une distance de \(String(format: "%.1f", distance)) km (ancien: \(existingWord.distance_km?.description ?? "nil") km)")
            
        } else {
            print("✅ Nouveau mot - création en base")
            
            // Conversion vers le format de base de données
            let dbWord = DatabaseWord(
                id: wordWithDistance.id,
                word: wordWithDistance.word,
                etymology: wordWithDistance.etymology.chain,
                shortDescription: wordWithDistance.shortDescription,
                distanceKm: distance
            )
            
            // Sauvegarder en base avec POST
            let url = baseURL.appendingPathComponent("etymologies")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(dbWord)
            
            do {
                let _: [DatabaseWord] = try await performRequest(request, decoder: decoder)
                print("💾 Mot '\(word.word)' sauvegardé avec une distance de \(String(format: "%.1f", distance)) km")
            } catch ServiceError.httpError(409) {
                // Conflit: le mot existe déjà (race condition) - récupérer l'ID du mot existant et mettre à jour
                print("⚠️ Conflit détecté lors de la création - recherche de l'ID du mot existant...")
                
                // Rechercher le mot existant pour obtenir son vrai ID
                let conflictSearchUrl = baseURL.appendingPathComponent("etymologies")
                    .appendingQueryItem("select", value: "id")
                    .appendingQueryItem("word", value: "eq.\(word.word)")
                    .appendingQueryItem("limit", value: "1")
                
                let conflictRequest = URLRequest(url: conflictSearchUrl)
                
                struct ConflictWordResult: Codable {
                    let id: String
                }
                
                let conflictResults: [ConflictWordResult] = try await performRequest(conflictRequest, decoder: decoder)
                
                guard let existingWordId = conflictResults.first?.id else {
                    print("❌ Impossible de trouver l'ID du mot en conflit")
                    throw ServiceError.invalidInput
                }
                
                print("🔍 ID du mot existant trouvé: \(existingWordId)")
                
                let updateUrl = baseURL.appendingPathComponent("etymologies")
                    .appendingQueryItem("id", value: "eq.\(existingWordId)")
                
                var updateRequest = URLRequest(url: updateUrl)
                updateRequest.httpMethod = "PATCH"
                updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                updateRequest.setValue("return=minimal", forHTTPHeaderField: "Prefer")
                
                let updateData: [String: Any] = [
                    "etymology": wordWithDistance.etymology.chain.map { entry in
                        [
                            "sourceWord": entry.sourceWord,
                            "language": entry.language,
                            "period": entry.period as Any,
                            "originalScript": entry.originalScript as Any,
                            "translation": entry.translation as Any
                        ]
                    },
                    "distance_km": distance
                ]
                updateRequest.httpBody = try JSONSerialization.data(withJSONObject: updateData)
                
                let _: EmptyResponse = try await performRequest(updateRequest, decoder: decoder)
                print("✅ Mot '\(word.word)' mis à jour suite au conflit avec une distance de \(String(format: "%.1f", distance)) km")
            }
        }
        
        // Mise à jour du cache avec le mot nouvellement créé/mis à jour
        temporaryWordCache[cleanWord(word.word)] = wordWithDistance
        cacheTimestamps[cleanWord(word.word)] = Date()
        savePersistentCache()
        
        // ✅ CORRECTION: Ne pas invalider le cache après sauvegarde
        // Le mot vient d'être créé/mis à jour, le cache contient la version la plus récente
        // L'invalidation causait des problèmes de réplication Supabase
        print("✅ Mot '\(word.word)' sauvegardé et mis en cache avec distance \(String(format: "%.1f", distance)) km")
        
        // Notifier le cache des kilomètres
        await KilometersCache.shared.addKilometers(distance)
        
        // Retourner la distance pour feedback utilisateur
        return distance
    }
    
    /// Met à jour rétroactivement les distances des mots existants qui n'en ont pas
    func updateExistingWordsWithDistances() async throws -> Int {
        print("🔄 Mise à jour rétroactive des distances...")
        
        // Récupérer tous les mots sans distance (shortDescription null)
        let url = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology,created_at")
            .appendingQueryItem("short_description", value: "is.null")
            .appendingQueryItem("limit", value: "1000")
        
        let request = URLRequest(url: url)
        let wordsWithoutDistance: [SupabaseWord] = try await performRequest(request, decoder: remarkableWordDecoder)
        
        print("📊 \(wordsWithoutDistance.count) mots trouvés sans distance")
        
        var updatedCount = 0
        
        for supabaseWord in wordsWithoutDistance {
            let word = supabaseWord.toWord()
            
            do {
                // Calculer la distance
                let distance = try await word.calculateEtymologicalDistance()
                
                // Mettre à jour en base avec PATCH
                let updateUrl = baseURL.appendingPathComponent("etymologies")
                    .appendingQueryItem("id", value: "eq.\(word.id)")
                
                var updateRequest = URLRequest(url: updateUrl)
                updateRequest.httpMethod = "PATCH"
                updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                updateRequest.setValue("return=minimal", forHTTPHeaderField: "Prefer")
                
                let updateData = ["short_description": String(distance)]
                updateRequest.httpBody = try JSONSerialization.data(withJSONObject: updateData)
                
                let _: EmptyResponse = try await performRequest(updateRequest, decoder: decoder)
                
                updatedCount += 1
                print("✅ Mot '\(word.word)' mis à jour avec \(String(format: "%.1f", distance)) km")
                
            } catch {
                print("❌ Erreur pour le mot '\(word.word)': \(error)")
            }
        }
        
        print("🎉 Mise à jour terminée: \(updatedCount) mots mis à jour")
        return updatedCount
    }
    
    /// Met à jour spécifiquement les mots avec distance_km nulle ou égale à 0
    func updateZeroDistanceWords() async throws -> Int {
        print("🔄 Mise à jour des mots avec distance nulle ou 0...")
        
        // Récupérer tous les mots avec distance_km nulle ou égale à 0
        let url = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology,distance_km")
            .appendingQueryItem("or", value: "(distance_km.is.null,distance_km.eq.0)")
            .appendingQueryItem("limit", value: "1000")
        
        let request = URLRequest(url: url)
        let wordsWithZeroDistance: [SupabaseWord] = try await performRequest(request, decoder: remarkableWordDecoder)
        
        print("📊 \(wordsWithZeroDistance.count) mots trouvés avec distance nulle ou 0")
        
        var updatedCount = 0
        
        for supabaseWord in wordsWithZeroDistance {
            let word = supabaseWord.toWord()
            
            // Vérifier que le mot a une étymologie suffisante pour calculer une distance
            guard word.etymology.chain.count >= 2 else {
                print("⚠️ Mot '\(word.word)' ignoré - étymologie insuffisante")
                continue
            }
            
            do {
                // Calculer la nouvelle distance
                let distance = try await word.calculateEtymologicalDistance()
                
                // Ignorer si la distance calculée est toujours 0
                guard distance > 0 else {
                    print("⚠️ Mot '\(word.word)' ignoré - distance calculée toujours à 0")
                    continue
                }
                
                // Mettre à jour en base avec PATCH
                let updateUrl = baseURL.appendingPathComponent("etymologies")
                    .appendingQueryItem("id", value: "eq.\(word.id)")
                
                var updateRequest = URLRequest(url: updateUrl)
                updateRequest.httpMethod = "PATCH"
                updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                updateRequest.setValue("return=minimal", forHTTPHeaderField: "Prefer")
                
                let updateData: [String: Any] = [
                    "distance_km": distance
                ]
                updateRequest.httpBody = try JSONSerialization.data(withJSONObject: updateData)
                
                let _: EmptyResponse = try await performRequest(updateRequest, decoder: decoder)
                
                updatedCount += 1
                print("✅ Mot '\(word.word)' mis à jour: 0 → \(String(format: "%.1f", distance)) km")
                
            } catch {
                print("❌ Erreur pour le mot '\(word.word)': \(error)")
            }
        }
        
        print("🎉 Mise à jour des distances nulles terminée: \(updatedCount) mots mis à jour")
        return updatedCount
    }
    
    /// Supprime les mots avec des étymologies trop courtes (nettoyage de la base)
    func cleanInsufficientEtymologies() async throws -> Int {
        print("🧹 Nettoyage des mots avec étymologies insuffisantes...")
        
        // Structure temporaire pour cette requête spécifique (sans created_at)
        struct SimpleSupabaseWord: Codable {
            let id: String
            let word: String
            let etymology: [EtymologyEntry]
            
            // Convertir vers notre structure Word interne (version simplifiée)
            func toWord() -> Word {
            return Word(
                    id: id,
                word: word,
                    etymology: DirectEtymology(chain: etymology),
                    language: "français",
                    source: "database",
                    createdAt: Date(), // Date factice
                    updatedAt: Date(), // Date factice
                    foundInCNRTL: false,
                    foundWithCNRTLAndClaude: nil,
                    isRemarkable: false,
                    shortDescription: nil,
                    distanceKm: nil,
                    isComposedWord: false,
                    components: [],
                    gptAnalysis: nil
                )
            }
        }
        
        // Récupérer tous les mots pour analyser leurs étymologies
        let url = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology")
            .appendingQueryItem("limit", value: "1000")
        
        let request = URLRequest(url: url)
        let allWords: [SimpleSupabaseWord] = try await performRequest(request, decoder: remarkableWordDecoder)
        
        print("📊 Analyse de \(allWords.count) mots...")
        
        var deletedCount = 0
        var wordsToDelete: [String] = []
        
        for supabaseWord in allWords {
            let word = supabaseWord.toWord()
            
            // Vérifier si l'étymologie est suffisante
            if word.etymology.chain.count < 2 {
                wordsToDelete.append(word.word)
                print("🗑️ Marqué pour suppression: '\(word.word)' (\(word.etymology.chain.count) étape(s))")
                continue
            }
            
            // Vérifier s'il y a une origine géographique
            let geographicalSteps = word.etymology.chain.filter { step in
                !step.language.lowercased().contains("dater") && 
                !step.language.lowercased().contains("date") &&
                step.language.lowercased() != "français"
            }
            
            if geographicalSteps.count < 1 {
                wordsToDelete.append(word.word)
                print("🗑️ Marqué pour suppression: '\(word.word)' (pas d'origine géographique)")
            }
        }
        
        // Supprimer les mots identifiés
        for wordToDelete in wordsToDelete {
            do {
                let deleteUrl = baseURL.appendingPathComponent("etymologies")
                    .appendingQueryItem("word", value: "eq.\(wordToDelete)")
                
                var deleteRequest = URLRequest(url: deleteUrl)
                deleteRequest.httpMethod = "DELETE"
                deleteRequest.setValue("return=minimal", forHTTPHeaderField: "Prefer")
                
                let _: EmptyResponse = try await performRequest(deleteRequest, decoder: decoder)
                
                deletedCount += 1
                print("✅ Mot '\(wordToDelete)' supprimé de la base")
                
                // Invalider le cache aussi
                await invalidateWordCache(wordToDelete)
                
            } catch {
                print("❌ Erreur lors de la suppression de '\(wordToDelete)': \(error)")
            }
        }
        
        print("🎉 Nettoyage terminé: \(deletedCount) mots supprimés")
        return deletedCount
    }
    
    /// Met à jour rétroactivement les distances stockées pour migrer vers distance_km
    func syncDistancesToNewColumn() async throws {
        print("🔄 Synchronisation des distances vers la nouvelle colonne distance_km...")
        
        // Récupérer tous les mots avec étymologie pour recalculer les distances
        let url = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology")
        
        let request = URLRequest(url: url)
        
        struct WordForSync: Codable {
            let id: String
            let word: String
            let etymology: [EtymologyEntry]
        }
        
        let words: [WordForSync] = try await performRequest(request, decoder: decoder)
        print("📊 \(words.count) mots à synchroniser...")
        
        var successCount = 0
        
        for word in words {
            do {
                // Créer un objet Word temporaire pour calculer la distance
                let tempWord = Word(
                    id: word.id,
                    word: word.word,
                    etymology: DirectEtymology(chain: word.etymology),
                    language: "français",
                    source: "CNRTL",
                    createdAt: Date(),
                    updatedAt: Date(),
                    foundInCNRTL: true,
                    foundWithCNRTLAndClaude: true,
                    isRemarkable: false,
                    shortDescription: nil,
                    distanceKm: nil,
                    isComposedWord: false,
                    components: [],
                    gptAnalysis: nil
                )
                
                // Calculer la distance
                let distance = try await tempWord.calculateEtymologicalDistance()
                
                // Mettre à jour la base avec la distance
                let updateUrl = baseURL.appendingPathComponent("etymologies")
                    .appendingQueryItem("id", value: "eq.\(word.id)")
                
                var updateRequest = URLRequest(url: updateUrl)
                updateRequest.httpMethod = "PATCH"
                updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                updateRequest.setValue("return=minimal", forHTTPHeaderField: "Prefer")
                
                let updateData: [String: Any] = [
                    "distance_km": distance
                ]
                updateRequest.httpBody = try JSONSerialization.data(withJSONObject: updateData)
                
                let _: EmptyResponse = try await performRequest(updateRequest, decoder: decoder)
                successCount += 1
                
                print("✅ Distance mise à jour pour '\(word.word)': \(String(format: "%.1f", distance)) km")
                
                // Petit délai pour éviter de surcharger l'API
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconde
                
        } catch {
                print("⚠️ Erreur lors de la mise à jour de '\(word.word)': \(error)")
            }
        }
        
        print("🎉 Synchronisation terminée: \(successCount)/\(words.count) mots mis à jour")
    }
    
    /// Récupère les mots créés depuis une date donnée
    func fetchRecentWords(since: Date) async throws -> [Word] {
        let url = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology,created_at,is_remarkable,distance_km,short_description")
            .appendingQueryItem("created_at", value: "gte.\(ISO8601DateFormatter().string(from: since))")
            .appendingQueryItem("created_at", value: "not.is.null")
            .appendingQueryItem("order", value: "created_at.desc")
        
        let request = URLRequest(url: url)
        
        struct RecentWordResponse: Codable {
            let id: String
            let word: String
            let etymology: [EtymologyEntry]
            let created_at: Date?
            let is_remarkable: Bool?
            let distance_km: Double?
            let short_description: String?
        }
        
        let responses: [RecentWordResponse] = try await performRequest(request, decoder: decoder)
        
        return responses.map { response in
            Word(
                id: response.id,
                word: response.word,
                etymology: DirectEtymology(chain: response.etymology),
                language: "français",
                source: "CNRTL",
                createdAt: response.created_at ?? Date(),
                updatedAt: response.created_at ?? Date(),
                foundInCNRTL: true,
                foundWithCNRTLAndClaude: true,
                isRemarkable: response.is_remarkable ?? false,
                shortDescription: response.short_description,
                distanceKm: response.distance_km,
                isComposedWord: false,
                components: [],
                gptAnalysis: nil
            )
        }
    }
    
    /// Récupère tous les mots de la base (tri alphabétique)
    func fetchAllWords() async throws -> [Word] {
        let url = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology,created_at,is_remarkable,distance_km,short_description")
            .appendingQueryItem("order", value: "word.asc")
        
        let request = URLRequest(url: url)
        
        struct AllWordResponse: Codable {
            let id: String
    let word: String
            let etymology: [EtymologyEntry]
            let created_at: Date?
            let is_remarkable: Bool?
            let distance_km: Double?
            let short_description: String?
        }
        
        let responses: [AllWordResponse] = try await performRequest(request, decoder: decoder)
        
        return responses.map { response in
            Word(
                id: response.id,
                word: response.word,
                etymology: DirectEtymology(chain: response.etymology),
                language: "français",
                source: "CNRTL",
                createdAt: response.created_at ?? Date(),
                updatedAt: response.created_at ?? Date(),
                foundInCNRTL: true,
                foundWithCNRTLAndClaude: true,
                isRemarkable: response.is_remarkable ?? false,
                shortDescription: response.short_description,
                distanceKm: response.distance_km,
                isComposedWord: false,
                components: [],
                gptAnalysis: nil
            )
        }
    }
    
    /// Récupère tous les mots de la base (tri par date de création)
    func fetchAllWordsByDate() async throws -> [Word] {
        let url = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("select", value: "id,word,etymology,created_at,is_remarkable,distance_km,short_description,is_composed_word,components")
            .appendingQueryItem("order", value: "created_at.desc")
            .appendingQueryItem("limit", value: "500")  // ✅ Limite explicite pour éviter le problème
        
        var request = URLRequest(url: url)
        // ✅ CORRECTION CRITIQUE: Forcer un rafraîchissement côté client comme fetchRemarkableWords
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        // ✅ CORRECTION: Utiliser SupabaseWord et remarkableWordDecoder comme fetchWord()
        let responses: [SupabaseWord] = try await performRequest(request, decoder: remarkableWordDecoder)
        
        let convertedWords = responses.map { supabaseWord in
            supabaseWord.toWord()
        }
        
        // 🔍 DIAGNOSTIC: Comparer avec fetchRemarkableWords
        let remarkableInCuration = convertedWords.filter { $0.isRemarkable }
        print("🔍 DIAGNOSTIC: Curation a \(remarkableInCuration.count) mots remarquables")
        print("🔍 DIAGNOSTIC: IDs remarquables curation: \(remarkableInCuration.prefix(5).map { $0.word })")
        
        // 🔍 DIAGNOSTIC SPÉCIFIQUE: Chercher "automobile"
        let automobile = convertedWords.first { $0.word == "automobile" }
        if let automobile = automobile {
            print("🔍 DIAGNOSTIC: 'automobile' trouvé dans curation: isRemarkable=\(automobile.isRemarkable)")
            } else {
            print("🔍 DIAGNOSTIC: 'automobile' MANQUANT dans fetchAllWordsByDate")
        }
        
        return convertedWords
    }
    
    /// Bascule le statut remarquable d'un mot
    func toggleRemarkableStatus(wordId: String, newStatus: Bool) async throws {
        print("🔄 Basculement du statut remarquable pour \(wordId): \(newStatus)")
        
        let url = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("id", value: "eq.\(wordId)")
        
        print("🔍 URL de basculement: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        let updateData: [String: Any] = [
            "is_remarkable": newStatus
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: updateData)
        
        print("🔍 Données envoyées: \(updateData)")
        
        do {
            let _: EmptyResponse = try await performRequest(request, decoder: decoder)
            print("✅ Statut remarquable mis à jour en base pour le mot \(wordId): \(newStatus)")
        } catch {
            print("❌ ERREUR lors du basculement pour \(wordId): \(error)")
            print("❌ Type d'erreur: \(type(of: error))")
            throw error
        }
    }
    
    /// Supprime un mot de la base de données
    func deleteWord(wordId: String) async throws {
        print("🗑️ Suppression du mot avec ID: \(wordId)")
        print("🔍 URL de suppression: \(baseURL.appendingPathComponent("etymologies").appendingQueryItem("id", value: "eq.\(wordId)"))")
        
        let url = baseURL.appendingPathComponent("etymologies")
            .appendingQueryItem("id", value: "eq.\(wordId)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        print("🔍 Envoi de la requête DELETE...")
        
        do {
            let _: EmptyResponse = try await performRequest(request, decoder: decoder)
            print("✅ Mot supprimé avec succès de la base")
            
            // Invalider le cache pour ce mot
            let word = temporaryWordCache.first { $0.value.id == wordId }?.key
            if let wordKey = word {
                temporaryWordCache.removeValue(forKey: wordKey)
                cacheTimestamps.removeValue(forKey: wordKey)
                print("🗑️ Cache invalidé pour le mot supprimé")
            }
        } catch {
            print("❌ Erreur lors de la suppression: \(error)")
            print("❌ Type d'erreur: \(type(of: error))")
            throw error
        }
    }
    
    // MARK: - Language Location Management
    
    /// Sauvegarde une nouvelle langue en base de données
    func saveLanguageLocation(_ newLanguage: NewLanguage) async throws {
        print("🌍 Sauvegarde de la nouvelle langue: \(newLanguage.name)")
        
        // Vérifier d'abord si la langue existe déjà
        let searchUrl = baseURL.appendingPathComponent("language_locations")
            .appendingQueryItem("select", value: "id,language")
            .appendingQueryItem("language", value: "ilike.\(newLanguage.name)")
            .appendingQueryItem("limit", value: "1")
        
        let searchRequest = URLRequest(url: searchUrl)
        
        struct ExistingLanguage: Codable {
            let id: String
    let language: String
}

        let existingLanguages: [ExistingLanguage] = try await performRequest(searchRequest, decoder: decoder)
        
        if !existingLanguages.isEmpty {
            print("⚠️ Langue '\(newLanguage.name)' existe déjà en base - pas de sauvegarde")
            return
        }
        
        // Créer l'objet LanguageLocation à sauvegarder
        let languageLocation = LanguageLocation(
            id: UUID(),
            language: newLanguage.name,
            latitude: newLanguage.latitude,
            longitude: newLanguage.longitude,
            city: newLanguage.description,
            period: HistoricalPeriod(start: newLanguage.period_start, end: newLanguage.period_end),
            abbreviations: [],
            description: newLanguage.reason
        )
        
        // Préparer la requête POST
        let url = baseURL.appendingPathComponent("language_locations")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(languageLocation)
        
        do {
            let _: EmptyResponse = try await performRequest(request, decoder: decoder)
            print("✅ Langue '\(newLanguage.name)' sauvegardée avec succès")
            
            // ✅ CORRECTION: Ajouter immédiatement au cache au lieu d'invalider
            if languageLocationsCache == nil {
                // Si le cache n'est pas encore chargé, le charger d'abord
                await preloadLanguageLocations()
            }
            
            // Ajouter la nouvelle langue au cache existant
            if var currentCache = languageLocationsCache {
                currentCache.append(languageLocation)
                languageLocationsCache = currentCache
                print("✅ Langue '\(newLanguage.name)' ajoutée au cache local")
            }
            
        } catch ServiceError.httpError(409) {
            print("⚠️ Conflit: Langue '\(newLanguage.name)' existe déjà")
        } catch {
            print("❌ Erreur lors de la sauvegarde de la langue: \(error)")
            throw error
        }
    }
    
    /// Vide tous les caches (pour forcer le rechargement depuis la base)
    func clearAllCaches() async {
        print("🧹 Vidage de tous les caches...")
        
        // Vider le cache temporaire des mots
        temporaryWordCache.removeAll()
        cacheTimestamps.removeAll()
        
        // Vider le cache persistant
        UserDefaults.standard.removeObject(forKey: "wordCache")
        UserDefaults.standard.removeObject(forKey: "cacheTimestamps")
        
        // Vider le cache des langues
        languageLocationsCache = nil
        
        // Vider le cache des kilomètres
        UserDefaults.standard.removeObject(forKey: "totalKilometers")
        
        print("✅ Tous les caches vidés")
    }
}

// MARK: - Extensions et Structures utilitaires

extension URL {
    func appendingQueryItem(_ name: String, value: String?) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
            return self
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: name, value: value))
        components.queryItems = queryItems
        return components.url ?? self
    }
}

// Structure vide pour les réponses sans contenu
private struct EmptyResponse: Codable {}

// Énumération pour la source de remarquabilité
enum RemarkableSource: String, Codable {
    case automatic = "automatic"
    case manual = "manual"
    case ai = "ai"
}

// Fonction utilitaire pour comparer les chaînes en ignorant les accents
private func compareIgnoringAccents(_ str1: String, _ str2: String) -> Bool {
    return str1.folding(options: .diacriticInsensitive, locale: .current)
        .lowercased() ==
        str2.folding(options: .diacriticInsensitive, locale: .current)
        .lowercased()
}

// Extension pour appel cross-actor depuis le main actor (SwiftUI)
extension SupabaseService {
    static func clearAllCachesFromMainActor() {
        Task {
            await SupabaseService.shared.clearAllCaches()
        }
    }
}

