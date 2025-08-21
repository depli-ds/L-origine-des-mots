import Foundation

enum LoadingState: Equatable {
    case idle
    case loadingWord
    case searchingCNRTL
    case extractingEtymology
    case loadingLanguages
    case analyzingWithClaude
    case fallbackToGPT5
    case processingNewLanguages([String])
    case calculatingDistance
    case analyzingWord
    case analyzingNewLanguage(String)
    case savingNewLanguage(String)
    case savingWord
    case error(String)
    
    var message: String {
        switch self {
        case .idle:
            return ""
        case .loadingWord:
            return "Recherche du mot..."
        case .searchingCNRTL:
            return "🔍 Consultation CNRTL.fr..."
        case .extractingEtymology:
            return "📝 Extraction des données étymologiques..."
        case .loadingLanguages:
            return "🗂️ Chargement des langues connues..."
        case .analyzingWithClaude:
            return "🤖 Analyse avec Claude IA..."
        case .fallbackToGPT5:
            return "🔄 Claude surchargé → Basculement GPT-5..."
        case .processingNewLanguages(let languages):
            let count = languages.count
            return "🌍 Traitement de \(count) nouvelle(s) langue(s)..."
        case .calculatingDistance:
            return "📏 Calcul des distances géographiques..."
        case .analyzingWord:
            return "Analyse étymologique en cours..."
        case .analyzingNewLanguage(let language):
            return "Analyse de la langue : \(language)"
        case .savingNewLanguage(let language):
            return "Sauvegarde de la langue : \(language)"
        case .savingWord:
            return "💾 Sauvegarde du mot..."
        case .error(let message):
            return "Erreur : \(message)"
        }
    }
    
    var isLoading: Bool {
        switch self {
        case .idle, .error:
            return false
        default:
            return true
        }
    }
    
    var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
    
    static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.loadingWord, .loadingWord),
             (.analyzingWord, .analyzingWord),
             (.savingWord, .savingWord):
            return true
        case (.analyzingNewLanguage(let l1), .analyzingNewLanguage(let l2)),
             (.savingNewLanguage(let l1), .savingNewLanguage(let l2)):
            return l1 == l2
        case (.error(let e1), .error(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
} 