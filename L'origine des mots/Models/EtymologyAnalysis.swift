import Foundation

// Structure pour l'analyse GPT
struct EtymologyAnalysis: Codable {
    let etymology: GPTEtymology
    let is_composed_word: Bool?
    let components: [String]?
    let new_languages: [NewLanguage]
}

// Renommé pour éviter le conflit
struct GPTEtymology: Codable {
    let chain: [EtymologyEntry]  // Utilise directement EtymologyEntry
}

struct NewLanguage: Codable {
    let name: String
    let description: String
    let latitude: Double
    let longitude: Double
    let period_start: String
    let period_end: String
    let reason: String
} 