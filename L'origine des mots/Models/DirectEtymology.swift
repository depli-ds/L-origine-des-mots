import Foundation

public struct DirectEtymology: Codable {
    public let chain: [EtymologyEntry]
    
    public init(chain: [EtymologyEntry]) {
        self.chain = chain
    }
}

public struct EtymologyEntry: Codable {
    public let sourceWord: String
    public let language: String
    public let period: String?
    public let originalScript: String?
    public let translation: String?
    
    public init(sourceWord: String,
                language: String,
                period: String? = nil,
                originalScript: String? = nil,
                translation: String? = nil) {
        self.sourceWord = sourceWord
        self.language = language
        self.period = period
        self.originalScript = originalScript
        self.translation = translation
    }
    
    // Initialisation custom pour gérer les anciens formats de BDD
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Essayer de décoder sourceWord avec les deux formats possibles
        if let sourceWord = try? container.decode(String.self, forKey: .sourceWord) {
            // Format moderne: "sourceWord"
            self.sourceWord = sourceWord
        } else if let sourceWord = try? container.decode(String.self, forKey: .sourceWordLegacy) {
            // Format legacy: "source_word"
            self.sourceWord = sourceWord
        } else {
            // ✅ CORRECTION: Fallback seulement si vraiment aucun des deux formats n'existe
            self.sourceWord = "mot_manquant"
            print("⚠️ sourceWord manquant (aucun format trouvé), utilisation de 'mot_manquant' comme fallback")
        }
        
        self.language = try container.decode(String.self, forKey: .language)
        self.period = try? container.decode(String.self, forKey: .period)
        
        // Gérer originalScript avec les deux formats aussi
        if let originalScript = try? container.decode(String.self, forKey: .originalScript) {
            self.originalScript = originalScript
        } else {
            self.originalScript = try? container.decode(String.self, forKey: .originalScriptLegacy)
        }
        
        self.translation = try? container.decode(String.self, forKey: .translation)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceWord, forKey: .sourceWord)
        try container.encode(language, forKey: .language)
        try container.encodeIfPresent(period, forKey: .period)
        try container.encodeIfPresent(originalScript, forKey: .originalScript)
        try container.encodeIfPresent(translation, forKey: .translation)
    }
    
    private enum CodingKeys: String, CodingKey {
        case sourceWord = "sourceWord"           // Format moderne
        case sourceWordLegacy = "source_word"    // Format legacy  
        case language
        case period
        case originalScript = "originalScript"   // Format moderne
        case originalScriptLegacy = "original_script" // Format legacy
        case translation
    }
}

public struct PreprocessedEtymology {
    let etymologyChain: String
    let sourceWords: [String]
    let firstAttestation: String?
    
    public init(etymologyChain: String, sourceWords: [String], firstAttestation: String? = nil) {
        self.etymologyChain = etymologyChain
        self.sourceWords = sourceWords
        self.firstAttestation = firstAttestation
    }
} 