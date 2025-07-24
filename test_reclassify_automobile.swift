import Foundation

// Script de test pour reclassifier automobile comme emprunt composé
// À exécuter depuis ContentView ou en debug

class AutomobileReclassifier {
    
    static func reclassifyAutomobile() async {
        print("🚗 Début de la reclassification d'automobile...")
        
        do {
            // 1. Chercher automobile
            if let automobile = try await SupabaseService.shared.fetchWord("automobile") {
                print("✅ Automobile trouvé: ID = \(automobile.id)")
                print("📊 État actuel: isComposedWord = \(automobile.isComposedWord)")
                print("📊 Composants actuels: \(automobile.components)")
                
                // 2. Reclassifier si nécessaire
                if !automobile.isComposedWord || automobile.components != ["auto-", "mobile"] {
                    print("🔧 Reclassification nécessaire...")
                    
                    try await SupabaseService.shared.reclassifyAsBorrowedComposition(
                        wordId: automobile.id,
                        components: ["auto-", "mobile"]
                    )
                    
                    print("🎉 Reclassification terminée !")
                    
                    // 3. Vérification
                    print("🔍 Vérification...")
                    if let updatedAutomobile = try await SupabaseService.shared.fetchWord("automobile") {
                        print("✅ Vérification réussie:")
                        print("   - isComposedWord: \(updatedAutomobile.isComposedWord)")
                        print("   - components: \(updatedAutomobile.components)")
                    }
                } else {
                    print("✅ Automobile déjà correctement classifié !")
                }
            } else {
                print("❌ Automobile non trouvé en base")
            }
        } catch {
            print("❌ Erreur lors de la reclassification: \(error)")
        }
    }
}

// Usage dans ContentView ou autre:
// Task {
//     await AutomobileReclassifier.reclassifyAutomobile()
// } 