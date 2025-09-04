import Foundation

// Structure pour les signalements avec dates
struct ReportedWord: Codable {
    let id: String
    let wordName: String
    let reportDate: Date
}

// États du bouton de signalement
enum ReportButtonState {
    case notReported
    case reported      // "Mot signalé (Annuler)"
    case corrected     // "Mot corrigé (Signaler à nouveau)"
    
    var buttonText: String {
        switch self {
        case .notReported: return "Signaler ce mot"
        case .reported: return "Mot signalé (Annuler)"
        case .corrected: return "Mot corrigé (Signaler à nouveau)"
        }
    }
}
