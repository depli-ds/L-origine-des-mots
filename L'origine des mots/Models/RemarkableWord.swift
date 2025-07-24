import Foundation

struct RemarkableWord: Identifiable, Codable {
    let id: UUID
    let word: String
    let shortDescription: String?
    let tags: [String]
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, word, tags
        case shortDescription = "why_remarkable"
        case createdAt = "created_at"
    }
}

// Source d'ajout du mot remarquable
enum AdditionSource: String, Codable, CaseIterable {
    case manual = "manual"
    case automatic = "automatic"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .manual:
            return "Manuel"
        case .automatic:
            return "Automatique"
        case .unknown:
            return "Inconnu"
        }
    }
    
    var icon: String {
        switch self {
        case .manual:
            return "hand.raised"
        case .automatic:
            return "brain.head.profile"
        case .unknown:
            return "questionmark.circle"
        }
    }
    
    var color: String {
        switch self {
        case .manual:
            return "blue"
        case .automatic:
            return "purple"
        case .unknown:
            return "gray"
        }
    }
} 