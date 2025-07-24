import Foundation

struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
    }
    
    struct Message: Codable {
        let content: String
    }
}

class OpenAIService {
    static let shared = OpenAIService()
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let session: URLSession
    private let apiKey: String
    
    init() {
        self.apiKey = Configuration.openAIKey
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30  // Plus long car GPT peut prendre du temps
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        
        // Headers par défaut
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(Configuration.openAIKey)"
        ]
        
        self.session = URLSession(configuration: config)
    }
    
    func sendMessage(_ message: String) async throws -> String {
        // Configuration de la requête
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Corps de la requête
        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "user", "content": message]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Envoi de la requête avec retry
        print("🤖 Envoi du message à OpenAI")
        print("📝 Longueur du message: \(message.count)")
        
        // Retry jusqu'à 3 fois pour les erreurs réseau temporaires
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ServiceError.invalidResponse
                }
                
                print("📍 Code HTTP: \(httpResponse.statusCode)")
                
                // Vérifier le code de statut
                switch httpResponse.statusCode {
                case 200:
                    // Succès - décoder la réponse
                    let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    return result.choices.first?.message.content ?? ""
                case 429:
                    // Rate limit - attendre et réessayer
                    print("⚠️ Rate limit atteint, attente de \(attempt * 2) secondes...")
                    try await Task.sleep(nanoseconds: UInt64(attempt * 2 * 1_000_000_000))
                    continue
                case 500...599:
                    // Erreur serveur - réessayer
                    print("⚠️ Erreur serveur \(httpResponse.statusCode), tentative \(attempt)/3")
                    if attempt < 3 {
                        try await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
                        continue
                    }
                    throw ServiceError.httpError(httpResponse.statusCode)
                default:
                    // Autres erreurs HTTP
                    throw ServiceError.httpError(httpResponse.statusCode)
                }
                
            } catch {
                lastError = error
                
                // Vérifier si c'est une erreur réseau temporaire
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .networkConnectionLost, .notConnectedToInternet, .timedOut:
                        print("⚠️ Erreur réseau temporaire (\(urlError.localizedDescription)), tentative \(attempt)/3")
                        if attempt < 3 {
                            try await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
                            continue
                        }
                    default:
                        break
                    }
                }
                
                // Si ce n'est pas une erreur temporaire ou si c'est la dernière tentative
                if attempt == 3 {
                    print("❌ Échec définitif après 3 tentatives: \(error)")
                    throw error
                }
            }
        }
        
        // Ne devrait jamais arriver, mais au cas où
        throw lastError ?? ServiceError.connectionFailed
    }
    
    func analyzeWithGPT4(_ prompt: String) async throws -> String {
        return try await sendMessage(prompt)
    }
}
