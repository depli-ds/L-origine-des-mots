import Foundation

/// Erreurs spécifiques à l'orchestration étymologique
enum EtymologyError: Error, LocalizedError {
    case insufficientEtymology(String)
    case analysisError(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .insufficientEtymology(let message):
            return "Étymologie insuffisante: \(message)"
        case .analysisError(let message):
            return "Erreur d'analyse: \(message)"
        case .networkError(let message):
            return "Erreur réseau: \(message)"
        }
    }
}

/// Service orchestrateur qui gère le flux complet d'analyse étymologique pour les nouveaux mots
class EtymologyOrchestrator {
    static let shared = EtymologyOrchestrator()
    
    private lazy var cnrtlService = CNRTLService.shared
    private lazy var textPreprocessor = TextPreprocessor(knownLanguages: [])
    
    private init() {}
    
    /// Orchestration complète : recherche + analyse + sauvegarde
    func processNewWord(_ word: String) async throws -> Word {
        print("\n🎯 Démarrage de l'orchestration pour le mot '\(word)'")
        
        // 1. Vérification CNRTL
        print("📚 Étape 1: Vérification CNRTL...")
        let (cnrtlURL, sourceState) = try await cnrtlService.fetchEtymology(for: word)
        
        // 2. Extraction du texte étymologique
        print("📝 Étape 2: Extraction du texte étymologique...")
        
        let etymologyText: String
        do {
            etymologyText = try await cnrtlService.fetchEtymologyText(from: cnrtlURL)
            print("✅ Texte extrait (\(etymologyText.count) caractères)")
        } catch CNRTLError.maxRedirectsReached {
            // Cas spécial pour les mots avec des références circulaires (comme "rouge")
            print("⚠️ Références circulaires détectées - tentative d'extraction directe...")
            
            // Au lieu de rejeter, essayons d'extraire le contenu directement
            do {
                etymologyText = try await extractEtymologyDirectly(from: cnrtlURL)
                print("✅ Extraction directe réussie (\(etymologyText.count) caractères)")
            } catch {
                print("❌ Échec de l'extraction directe: \(error)")
                throw EtymologyError.networkError("Le mot '\(word)' contient des références circulaires sur CNRTL et l'extraction directe a échoué.")
            }
        } catch CNRTLError.sectionNotFound {
            // Cas spécial pour les mots avec des sections d'étymologie non standard ou fausses références (comme "robot")
            print("⚠️ Section étymologique non trouvée par le service standard - tentative d'extraction directe...")
            
            do {
                etymologyText = try await extractEtymologyDirectly(from: cnrtlURL)
                print("✅ Extraction directe réussie (\(etymologyText.count) caractères)")
            } catch {
                print("❌ Échec de l'extraction directe: \(error)")
                throw EtymologyError.networkError("Le mot '\(word)' n'a pas pu être extrait depuis CNRTL malgré les tentatives d'extraction directe.")
            }
        }
        
        // 3. Récupération des langues connues
        print("🗂️ Étape 3: Récupération des langues connues...")
        let knownLanguages = try await SupabaseService.shared.fetchLanguageNames()
        print("✅ \(knownLanguages.count) langues connues chargées")
        
        // 4. Analyse avec Claude (service principal)
        print("🤖 Étape 4: Analyse avec Claude...")
        let etymologyAnalysis = try await ClaudeService.shared.analyzeEtymology(etymologyText, knownLanguages: knownLanguages)
        print("✅ Analyse Claude terminée - \(etymologyAnalysis.etymology.chain.count) étapes étymologiques")
        
        // 5. Validation : Identifier les mots avec des étymologies trop simples (sans rejeter)
        var hasMinimumEtymology = true
        var hasGeographicalOrigin = true
        
        if etymologyAnalysis.etymology.chain.count < 2 {
            print("⚠️ Mot '\(word)' avec étymologie courte (\(etymologyAnalysis.etymology.chain.count) étape(s))")
            print("   Détail: \(etymologyAnalysis.etymology.chain.map { $0.sourceWord }.joined(separator: " -> "))")
            hasMinimumEtymology = false
            // Mais on ne rejette plus - on sauvegarde quand même
        }
        
        // Validation additionnelle : Vérifier s'il y a au moins une véritable origine géographique
        let geographicalSteps = etymologyAnalysis.etymology.chain.filter { step in
            !step.language.lowercased().contains("dater") && 
            !step.language.lowercased().contains("date") &&
            step.language.lowercased() != "français"
        }
        
        if geographicalSteps.count < 1 {
            print("⚠️ Mot '\(word)' sans origine géographique claire")
            print("   Étapes analysées: \(etymologyAnalysis.etymology.chain.map { "\($0.sourceWord) (\($0.language))" }.joined(separator: " -> "))")
            hasGeographicalOrigin = false
            // Mais on ne rejette plus - on sauvegarde quand même
        } else {
            print("✅ Validation réussie : \(geographicalSteps.count) étape(s) géographique(s) valide(s)")
        }
        
        // 6. Gestion des nouvelles langues si nécessaire
        if !etymologyAnalysis.new_languages.isEmpty {
            print("🌍 Étape 5: Traitement de \(etymologyAnalysis.new_languages.count) nouvelles langues...")
            await processNewLanguages(etymologyAnalysis.new_languages)
            
            // Attendre un peu pour la réplication Supabase et forcer le rechargement du cache
            print("⏱️ Attente de la réplication des nouvelles langues...")
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 seconde
            
            // Forcer le rechargement du cache des langues pour inclure Taïno
            await SupabaseService.shared.preloadLanguageLocations()
            print("✅ Cache des langues rechargé avec les nouvelles langues")
        }
        
        // 7. Création de l'objet Word
        print("📦 Étape 6: Création de l'objet Word...")
        let newWord = Word(
            id: UUID().uuidString,
            word: word.lowercased().trimmingCharacters(in: .whitespaces),
            etymology: DirectEtymology(chain: etymologyAnalysis.etymology.chain),
            language: "français",
            source: "CNRTL + Claude",
            createdAt: Date(),
            updatedAt: Date(),
            foundInCNRTL: sourceState == .foundInCNRTL,
            foundWithCNRTLAndClaude: true,
            isRemarkable: false,
            // Marquer spécifiquement les mots sans déplacement avec un indicateur spécial
            shortDescription: (!hasMinimumEtymology || !hasGeographicalOrigin) ? "0" : nil, // Distance nulle si pas de déplacement
            distanceKm: nil,  // Sera calculé lors de la sauvegarde
            isComposedWord: etymologyAnalysis.is_composed_word ?? false,
            components: etymologyAnalysis.components ?? [],
            gptAnalysis: etymologyAnalysis
        )
        
        // 8. Sauvegarde avec calcul automatique de distance
        print("💾 Étape 7: Sauvegarde avec calcul de distance...")
        let distance = try await SupabaseService.shared.saveWordWithDistance(newWord)
        print("🎉 Mot '\(word)' ajouté avec succès ! Distance: \(String(format: "%.1f", distance)) km")
        
        // ✅ CORRECTION: Retourner un Word avec la distance mise à jour
        let wordWithDistance = Word(
            id: newWord.id,
            word: newWord.word,
            etymology: newWord.etymology,
            language: newWord.language,
            source: newWord.source,
            createdAt: newWord.createdAt,
            updatedAt: newWord.updatedAt,
            foundInCNRTL: newWord.foundInCNRTL,
            foundWithCNRTLAndClaude: newWord.foundWithCNRTLAndClaude,
            isRemarkable: newWord.isRemarkable,
            shortDescription: newWord.shortDescription,
            distanceKm: distance,  // ✅ Mettre à jour avec la distance calculée
            isComposedWord: newWord.isComposedWord,
            components: newWord.components,
            gptAnalysis: newWord.gptAnalysis
        )
        
        return wordWithDistance
    }
    
    /// Traitement des nouvelles langues identifiées avec sauvegarde en base
    private func processNewLanguages(_ newLanguages: [NewLanguage]) async {
        for language in newLanguages {
            print("🌍 Nouvelle langue détectée: \(language.name)")
            print("   📍 Localisation: \(language.description) (\(language.latitude), \(language.longitude))")
            print("   📅 Période: \(language.period_start) - \(language.period_end)")
            print("   💡 Raison: \(language.reason)")
            
            // ✅ Sauvegarder la nouvelle langue en base
            do {
                try await SupabaseService.shared.saveLanguageLocation(language)
            } catch {
                print("❌ Erreur lors de la sauvegarde de la langue '\(language.name)': \(error)")
                // On continue avec les autres langues même si une échoue
            }
        }
    }    
    /// Extrait l'étymologie directement d'une page CNRTL sans suivre les références
    private func extractEtymologyDirectly(from urlString: String) async throws -> String {
        print("🔧 Extraction directe d'étymologie depuis: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            throw EtymologyError.networkError("URL invalide: \(urlString)")
        }
        
        let session = URLSession.shared
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw EtymologyError.networkError("Impossible de décoder la page HTML")
        }
        
        // Patterns d'étymologie étendus pour couvrir différents formats
        let etymologyPatterns = [
            "[ÉE]TYMOL\\.", // Pattern standard
            "\\*\\*[ÉE]tymol\\. et Hist\\.\\*\\*", // **Étymol. et Hist.** pour robot
            "[ÉE]TYMOL\\. ET HIST\\.", // ÉTYMOL. ET HIST. en majuscules
            "[ÉE]tym\\. et Hist\\.", // Etym. et Hist.
            "[ÉE]tym\\." // "Etym." au lieu de "ÉTYMOL."
        ]
        
        for pattern in etymologyPatterns {
            if let start = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                print("🎯 Pattern d'étymologie trouvé: \(pattern)")
                
                // Chercher la fin de la section
                let searchRange = start.upperBound..<html.endIndex
                let endPatterns = [
                    "</td>", // Fin de cellule de tableau
                    "<div", "<p>", "<h[1-6]", 
                    "HIST\\.", "SYNT\\.", "REM\\.",
                    "\\*\\*[A-Z]+\\*\\*", // Autre section en gras
                    "©.*?CNRTL" // Copyright
                ]
                
                var closestEnd: String.Index = html.endIndex
                for endPattern in endPatterns {
                    if let endRange = html.range(of: endPattern, options: [.regularExpression, .caseInsensitive], range: searchRange) {
                        if endRange.lowerBound < closestEnd {
                            closestEnd = endRange.lowerBound
                        }
                    }
                }
                
                var etymologyText = String(html[start.lowerBound..<closestEnd])
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression) // Remplacer par espace
                    .replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression) // Enlever les balises gras markdown
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Ne plus supprimer les références - laisser Claude faire le tri
                etymologyText = etymologyText
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if etymologyText.count >= 50 {
                    print("✅ Étymologie extraite directement (\(etymologyText.count) caractères)")
                    print("📝 Aperçu: \(String(etymologyText.prefix(150)))...")
                    return etymologyText
                }
            }
        }
        
        // Si aucun pattern ne fonctionne, essayer une extraction générale
        throw EtymologyError.analysisError("Impossible d'extraire l'étymologie de la page")
    }
} 