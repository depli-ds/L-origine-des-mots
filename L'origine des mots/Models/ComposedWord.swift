import Foundation

/// Modèle pour représenter un mot composé avec ses composants
struct ComposedWord {
    let originalWord: String
    let components: [String]
    let etymologyText: String
    
    /// Indique si ce mot doit être traité comme composé
    var isComposed: Bool {
        return components.count >= 2
    }
} 