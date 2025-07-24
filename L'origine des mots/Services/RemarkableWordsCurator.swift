import Foundation
import Combine

// Erreurs spécifiques à la curation
enum CurationError: LocalizedError {
    case rateLimited(waitTime: TimeInterval)
    case claudeOverloaded
    case noRecentWords
    
    var errorDescription: String? {
        switch self {
        case .rateLimited(let waitTime):
            return "Limitation de débit: veuillez attendre \(Int(waitTime)) secondes"
        case .claudeOverloaded:
            return "Claude est temporairement surchargé, réessayez dans quelques minutes"
        case .noRecentWords:
            return "Aucun mot récent à analyser"
        }
    }
}

@MainActor
class RemarkableWordsCurator: ObservableObject {
    static let shared = RemarkableWordsCurator()
    
    // Publisher pour notifier les changements
    @Published var newWordsAdded: [RemarkableWord] = []
    
    // Limitation des requêtes pour éviter l'overload de Claude
    private var lastCurationTime: Date?
    private let minimumCurationInterval: TimeInterval = 60 // 1 minute minimum entre 2 curations
    
    private init() {}
    
    // Prompt pour Claude pour analyser la remarquabilité des mots
    private let curationPrompt = """
    Tu es un expert en étymologie chargé de sélectionner des mots remarquables pour une application éducative.

    Analyse cette liste de mots et leur étymologie, puis sélectionne uniquement les plus remarquables selon ces critères :

    CRITÈRES DE REMARQUABILITÉ :
    - Voyage géographique fascinant (plusieurs continents, routes commerciales historiques)
    - Évolution sémantique surprenante (changement de sens radical)
    - Passage par des langues anciennes ou "exotiques" (sanskrit, arabe, nahuatl, etc.)
    - Histoire culturelle intéressante (emprunts liés à des événements historiques)
    - Anecdotes étymologiques captivantes

    ÉVITER :
    - Étymologies simples ou directes (français → latin → grec)
    - Mots trop techniques ou spécialisés
    - Évolutions trop prévisibles

    Pour chaque mot sélectionné, fournis :
    1. Le mot
    2. Une description courte et engageante (max 80 caractères)
    3. 2-3 tags pertinents parmi : alimentation, arabe, grec, latin, sanskrit, perse, chinois, nahuatl, turc, sciences, vêtements, objets, histoire, jeux, mathématiques, médecine, marine, religion, technique

    Format de réponse JSON :
    {
      "selected_words": [
        {
          "word": "mot",
          "description": "Description courte et captivante",
          "tags": ["tag1", "tag2"]
        }
      ]
    }

    Sélectionne maximum 5 mots les plus remarquables de la liste.

    MOTS À ANALYSER :
    """
    
    // Analyse des mots récents pour curation
    func analyzeRecentWordsForCuration(since date: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()) async throws -> [RemarkableWord] {
        print("🔍 Analyse des mots récents pour curation...")
        print("📅 Cette fonctionnalité est temporairement désactivée")
        
        // TODO: Implémenter une nouvelle méthode pour récupérer les mots récents
        throw CurationError.noRecentWords
    }
    
    // Curation complète : analyse + ajout en base
    func performFullCuration() async throws -> Int {
        print("🎯 Démarrage de la curation complète...")
        print("ℹ️ Fonctionnalité de curation automatique temporairement désactivée")
        print("💡 Utilisez l'ajout manuel de mots remarquables")
        
        // Vérifier si assez de temps s'est écoulé depuis la dernière curation
        if let lastTime = lastCurationTime {
            let timeSinceLastCuration = Date().timeIntervalSince(lastTime)
            if timeSinceLastCuration < minimumCurationInterval {
                let waitTime = minimumCurationInterval - timeSinceLastCuration
                print("⏱️ Limitation de débit : dernière curation il y a \(Int(timeSinceLastCuration))s")
                print("⏳ Veuillez attendre encore \(Int(waitTime))s avant la prochaine curation")
                throw CurationError.rateLimited(waitTime: waitTime)
            }
        }
        
        // Marquer le temps même si aucune curation effectuée
        lastCurationTime = Date()
        
        print("⚠️ Aucune curation automatique effectuée - fonctionnalité désactivée")
        return 0
    }
    
    // Vider le cache de notification
    func clearNewWordsNotification() {
        newWordsAdded = []
    }
    
    // Régénérer une sélection aléatoire intelligente
    func generateRandomSelection(from allWords: [RemarkableWord], count: Int = 20) -> [RemarkableWord] {
        // Grouper par tags pour avoir de la diversité
        let tagGroups = Dictionary(grouping: allWords) { word in
            word.tags.first ?? "divers"
        }
        
        var selectedWords: [RemarkableWord] = []
        var remainingCount = count
        
        // Prendre au moins un mot de chaque catégorie représentée
        for (_, words) in tagGroups.shuffled() {
            if remainingCount <= 0 { break }
            if let word = words.randomElement() {
                selectedWords.append(word)
                remainingCount -= 1
            }
        }
        
        // Compléter avec des mots aléatoires s'il en manque
        let selectedWordIds = Set(selectedWords.map { $0.id })
        let remainingWords = allWords.filter { !selectedWordIds.contains($0.id) }
        selectedWords.append(contentsOf: remainingWords.shuffled().prefix(remainingCount))
        
        return Array(selectedWords.shuffled().prefix(count))
    }
} 