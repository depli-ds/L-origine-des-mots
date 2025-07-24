import Foundation

enum ServiceError: LocalizedError {
    // Erreurs réseau
    case connectionFailed
    case invalidResponse
    case invalidURL
    case httpError(Int)
    case noData
    case networkError(Error)
    case parsingError
    case invalidData
    case decodingError
    case decodingFailed(String)
    case operationInProgress
    case resourceNotFound
    case notAuthorized
    
    // Erreurs base de données
    case insertionFailed
    case fetchFailed
    case noEtymologyFound
    
    // Erreurs IA
    case tokenLimitExceeded
    
    // Erreurs Wiktionary/CNRTL
    case noEtymology
    case sectionNotFound
    
    // Erreurs Speech
    case notAvailable
    case recognitionFailed
    case noRecognizer
    case speechRecognitionNotAvailable
    case speechRecognitionDenied
    case speechRecognitionRestricted
    case microphoneDenied
    
    // Erreurs encodage
    case encodingError
    
    // Nouvel erreur
    case invalidInput
    case notImplemented
    
    var errorDescription: String? {
        switch self {
        // Erreurs réseau
        case .connectionFailed:
            return "La connexion au serveur a échoué"
        case .invalidResponse:
            return "Réponse invalide du serveur"
        case .invalidURL:
            return "URL invalide"
        case .httpError(let code):
            return "Erreur HTTP: \(code)"
        case .noData:
            return "Données non disponibles"
        case .networkError(let error):
            return "Erreur réseau: \(error.localizedDescription)"
        case .parsingError:
            return "Erreur lors de l'analyse des données"
        case .invalidData:
            return "Données invalides"
        case .decodingError:
            return "Erreur de décodage"
        case .decodingFailed(let details):
            return "Erreur de décodage: \(details)"
        case .operationInProgress:
            return "Une opération est déjà en cours"
        case .resourceNotFound:
            return "La ressource demandée n'a pas été trouvée"
        case .notAuthorized:
            return "Non autorisé"
            
        // Erreurs base de données
        case .insertionFailed:
            return "Échec de l'insertion en base de données"
        case .fetchFailed:
            return "Échec de la récupération des données"
        case .noEtymologyFound:
            return "Aucune étymologie trouvée"
            
        // Erreurs IA
        case .tokenLimitExceeded:
            return "Limite de tokens dépassée"
            
        // Erreurs Wiktionary/CNRTL
        case .noEtymology:
            return "Pas d'étymologie trouvée"
        case .sectionNotFound:
            return "Section non trouvée"
            
        // Erreurs Speech
        case .notAvailable:
            return "Service non disponible"
        case .recognitionFailed:
            return "Échec de la reconnaissance vocale"
        case .noRecognizer:
            return "Reconnaissance vocale non disponible"
        case .speechRecognitionNotAvailable:
            return "Reconnaissance vocale non disponible"
        case .speechRecognitionDenied:
            return "Accès à la reconnaissance vocale refusé"
        case .speechRecognitionRestricted:
            return "Reconnaissance vocale restreinte"
        case .microphoneDenied:
            return "Accès au microphone refusé"
            
        // Erreurs encodage
        case .encodingError:
            return "Erreur lors de l'encodage des données"
            
        // Nouvel erreur
        case .invalidInput:
            return "Entrée invalide"
        case .notImplemented:
            return "Fonctionnalité non implémentée"
        }
    }
} 