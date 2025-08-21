import Foundation

enum CNRTLError: Error {
    case invalidURL
    case networkError
    case serviceUnavailable
    case wordNotFound
    case sectionNotFound
    case maxRedirectsReached
}

class CNRTLService {
    static let shared = CNRTLService()
    private let maxRedirects = 3
    
    private init() {}
    
    func fetchEtymology(for word: String) async throws -> (String, SourceState) {
        let url = URL(string: "https://www.cnrtl.fr/etymologie/\(word)")!
        print("\n📚 Vérification CNRTL pour '\(word)'")
        print("📍 URL:", url.absoluteString)
        
        let session = createSession()
        defer { session.invalidateAndCancel() }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CNRTLError.networkError
        }
        
        print("📥 Code HTTP:", httpResponse.statusCode)
        
        if httpResponse.statusCode == 200,
           let html = String(data: data, encoding: .utf8),
           !html.contains("Cette forme est introuvable") {
            print("✅ Page CNRTL trouvée")
            return (url.absoluteString, .foundInCNRTL)
        }
        
        print("❌ Page non trouvée")
        throw CNRTLError.wordNotFound
    }
    
    func fetchEtymologyText(from url: String) async throws -> String {
        return try await fetchEtymologyTextWithRedirects(from: url, redirectCount: 0)
    }
    
    private func fetchEtymologyTextWithRedirects(from url: String, redirectCount: Int) async throws -> String {
        // Protection contre les boucles infinies
        guard redirectCount < 3 else {
            print("❌ Trop de redirections CNRTL (max 3)")
            throw CNRTLError.maxRedirectsReached
        }
        
        let url = URL(string: url)!
        let session = createSession()
        defer { session.invalidateAndCancel() }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw CNRTLError.networkError
        }
        
        
        // NOUVELLE APPROCHE : Extraction basée sur la structure HTML fixe de CNRTL
        print("🏗️ Extraction basée sur la structure HTML fixe (div#contentbox)")
        
        // 1. Vérifier d'abord si le mot n'existe pas
        let quickCheck = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        if quickCheck.contains("Cette forme est introuvable") || quickCheck.contains("introuvable") {
            print("❌ Mot introuvable sur CNRTL")
            throw CNRTLError.sectionNotFound
        }
        
        // 2. Extraction ciblée avec la structure HTML fixe : <div id="contentbox">...</div>
        if let contentboxStart = html.range(of: "<div id=\"contentbox\">"),
           let contentboxEnd = html.range(of: "</div></td></tr></table></div>", range: contentboxStart.upperBound..<html.endIndex) {
            
            let contentboxSection = String(html[contentboxStart.upperBound..<contentboxEnd.lowerBound])
            let cleanedEtymology = contentboxSection
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if cleanedEtymology.count >= 100 {
                print("🎯 Section étymologique extraite via structure HTML (\(cleanedEtymology.count) caractères)")
                print("📝 Aperçu: \(String(cleanedEtymology.prefix(150)))...")
                
                // Vérification pour les redirections EXPLICITES uniquement (pas dans le contenu étymologique)
                // Ne faire une redirection que si c'est un contenu court avec une vraie instruction de redirection
                if cleanedEtymology.count < 300 && (cleanedEtymology.contains("Voir aussi ") ||
                   cleanedEtymology.hasPrefix("Voir ") || cleanedEtymology.hasPrefix("V. ")) {
                    if let redirectReference = detectCNRTLReference(in: cleanedEtymology) {
                        print("🔄 Référence de redirection détectée vers: \(redirectReference)")
                        let newUrl = "https://www.cnrtl.fr/etymologie/\(redirectReference)"
                        return try await fetchEtymologyTextWithRedirects(from: newUrl, redirectCount: redirectCount + 1)
                    }
                }
                
                print("✅ Contenu étymologique riche conservé (pas de redirection)")                
                return cleanedEtymology
            }
        }
        
        print("⚠️ Extraction structurelle échouée, fallback vers nettoyage complet")
        
        // 3. Fallback vers l'approche précédente (au cas où la structure change)
        let cleanedText = html
            .replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("📄 Contenu complet nettoyé (\(cleanedText.count) caractères) - Claude analysera tout")
        // Vérification minimale pour les redirections
        if cleanedText.count < 500 || cleanedText.contains("Voir ") || cleanedText.contains("V. ") {
            if let redirectReference = detectCNRTLReference(in: cleanedText) {
                print("🔄 Référence détectée vers: \(redirectReference)")
                let newUrl = "https://www.cnrtl.fr/etymologie/\(redirectReference)"
                return try await fetchEtymologyTextWithRedirects(from: newUrl, redirectCount: redirectCount + 1)
            }
        }
        
        if cleanedText.count < 100 {
            print("❌ Page CNRTL trop courte ou vide")
            throw CNRTLError.sectionNotFound
        }
        
        return cleanedText
    }
    
    // Détecter les références vers d'autres entrées CNRTL
    private func detectCNRTLReference(in text: String) -> String? {
        // Patterns pour détecter les références
        let referencePatterns = [
            "Voir\\s+([a-zA-ZÀ-ÿ0-9]+)", // "Voir cravate2"
            "V\\.\\s+([a-zA-ZÀ-ÿ0-9]+)", // "V. cravate2"
            "Cf\\.\\s+([a-zA-ZÀ-ÿ0-9]+)", // "Cf. cravate2"
            "([a-zA-ZÀ-ÿ]+\\d+)" // Détecter directement "cravate2"
        ]
        
        for pattern in referencePatterns {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let match = String(text[range])
                
                // Extraire le mot de référence
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let nsText = text as NSString
                    let results = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
                    
                    if let result = results.first, result.numberOfRanges > 1 {
                        let referenceRange = result.range(at: 1)
                        if referenceRange.location != NSNotFound {
                            let reference = nsText.substring(with: referenceRange)
                            print("🎯 Référence extraite: '\(reference)' du pattern '\(pattern)'")
                            return reference
                        }
                    }
                }
                
                print("🎯 Référence brute trouvée: '\(match)'")
                return match.components(separatedBy: .whitespaces).last
            }
        }
        
        return nil
    }
    
    // Méthode simplifiée - SUPPRIMÉE : maintenant Claude analyse tout
    private func tryAlternativeExtractionMethods_DEPRECATED(from html: String) -> String? {
        print("🔧 Tentatives d'extraction alternatives...")
        
        // Méthode 1: Chercher d'autres patterns d'étymologie
        let alternativePatterns = [
            "[ÉE]tym\\. et Hist\\.", // Etym. et Hist. - pattern exact pour hamac (priorité)
            "[ÉE]TYMOL\\. ET HIST\\.", // ÉTYMOL. ET HIST. en majuscules
            "[ÉE]tym\\. et Hist\\.", // Etym. et Hist. - pattern exact pour hamac (priorité)
            "\\*\\*[ÉE]tymol\\. et Hist\\.\\*\\*", // **Étymol. et Hist.** pour robot
            "[ÉE]tym\\.", // "Etym." au lieu de "ÉTYMOL."
            "Origine", // Section "Origine"
            "Histoire du mot", // Section "Histoire du mot"
            "Étymologie" // Section "Étymologie" explicite
        ]
        
        for pattern in alternativePatterns {
            if let start = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                print("🎯 Pattern alternatif trouvé: \(pattern)")
                
                // Pour le pattern spécifique de robot, chercher jusqu'au prochain pattern de fin
                let searchRange = start.upperBound..<html.endIndex
                let endPatterns = [
                    "</td>", // Fin de cellule de tableau
                    "<div", "<p", "<h", 
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
                
                let etymologyText = String(html[start.lowerBound..<closestEnd])
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression) // Remplacer par espace, pas vide
                    .replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression) // Enlever les balises gras markdown
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if etymologyText.count >= 50 { // Seuil adapté pour les textes riches
                    print("✅ Extraction alternative réussie (\(etymologyText.count) caractères)")
                    print("📝 Aperçu: \(String(etymologyText.prefix(100)))...")
            return etymologyText
                }
            }
        }
        
        // Méthode 2: Chercher dans le contenu général de la page
        if let bodyMatch = extractFromGeneralContent(html) {
            return bodyMatch
        }
        
        // Méthode 3: Extraction spécifique pour les tableaux CNRTL
        if let tableContent = extractFromCNRTLTable(html) {
            return tableContent
        }
        
        print("❌ Toutes les méthodes d'extraction alternatives ont échoué")
        return nil
    }
    
    // Nouvelle méthode pour extraire depuis les tableaux CNRTL
    private func extractFromCNRTLTable(_ html: String) -> String? {
        print("🔍 Extraction depuis tableau CNRTL...")
        
        // Chercher le contenu dans les cellules de tableau qui contiennent de l'étymologie
        if let tableMatch = html.range(of: "<td[^>]*>.*?[ÉE]tym.*?</td>", options: [.regularExpression, .caseInsensitive, ]) {
            let tableContent = String(html[tableMatch])
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if tableContent.count >= 50 {
                print("✅ Extraction depuis tableau réussie (\(tableContent.count) caractères)")
                return tableContent
            }
        }
        
        return nil
    }
    
    private func extractFromGeneralContent(_ html: String) -> String? {
        print("🔍 Extraction depuis le contenu général de la page...")
        
        // Nettoyer le HTML et chercher des patterns étymologiques
        let cleanedContent = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Patterns pour identifier du contenu étymologique dans le texte général
        let etymologyIndicators = [
            "emprunté.*?à",
            "du.*?latin",
            "du.*?grec", 
            "de l'.*?arabe",
            "du.*?français",
            "issu.*?de",
            "tiré.*?de",
            "attesté.*?en",
            "première.*?attestation",
            "Mot.*?tchèque", // Spécifique pour robot
            "formé.*?sur" // Autre pattern pour robot
        ]
        
        for indicator in etymologyIndicators {
            if let range = cleanedContent.range(of: indicator, options: [.regularExpression, .caseInsensitive]) {
                print("🎯 Indicateur étymologique trouvé: \(indicator)")
                
                // Extraire une phrase ou deux autour de cet indicateur
                let start = max(cleanedContent.startIndex, cleanedContent.index(range.lowerBound, offsetBy: -50, limitedBy: cleanedContent.startIndex) ?? range.lowerBound)
                let end = min(cleanedContent.endIndex, cleanedContent.index(range.upperBound, offsetBy: 200, limitedBy: cleanedContent.endIndex) ?? range.upperBound)
                
                let extractedText = String(cleanedContent[start..<end])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if extractedText.count >= 30 {
                    print("✅ Contenu étymologique extrait (\(extractedText.count) caractères)")
                    return extractedText
                }
            }
        }
        
        return nil
    }
    
    private func createSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }
 // MARK: - Détection des mots composés

/// Détecte si un texte étymologique indique un mot composé et extrait les composants
func detectComposedWord(in etymologyText: String) -> [String]? {
    print("🔍 Analyse du texte pour détecter un mot composé...")
    print("📝 Texte analysé: \(String(etymologyText.prefix(200)))...")
    
    // Patterns pour détecter les mots composés dans le CNRTL
    let composedPatterns = [
        // Pattern principal: "Composé de l'élément préf. auto-1* et de mobile*"
        "Composé de l'élément préf\\. ([a-zA-ZÀ-ÿ-]+).*?et de ([a-zA-ZÀ-ÿ-]+)",
        // "Composé de auto et mobile"
        "Composé de ([a-zA-ZÀ-ÿ-]+) et (?:de )?([a-zA-ZÀ-ÿ-]+)",
        // "formé de X et Y"
        "formé de ([a-zA-ZÀ-ÿ-]+) et (?:de )?([a-zA-ZÀ-ÿ-]+)",
        // "Dérivé de X et Y"
        "Dérivé de ([a-zA-ZÀ-ÿ-]+) et (?:de )?([a-zA-ZÀ-ÿ-]+)",
        // "de X + Y"
        "de ([a-zA-ZÀ-ÿ-]+) \\+ ([a-zA-ZÀ-ÿ-]+)",
        // "préf. auto- et mobile"
        "préf\\. ([a-zA-ZÀ-ÿ-]+) et ([a-zA-ZÀ-ÿ-]+)"
    ]
    
    for pattern in composedPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let nsText = etymologyText as NSString
            let results = regex.matches(in: etymologyText, range: NSRange(location: 0, length: nsText.length))
            
            if let result = results.first, result.numberOfRanges >= 3 {
                let component1Range = result.range(at: 1)
                let component2Range = result.range(at: 2)
                
                if component1Range.location != NSNotFound && component2Range.location != NSNotFound {
                    let component1 = nsText.substring(with: component1Range)
                        .replacingOccurrences(of: "-[0-9*]*", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "\\*", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let component2 = nsText.substring(with: component2Range)
                        .replacingOccurrences(of: "-[0-9*]*", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "\\*", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Validation des composants
                    if component1.count >= 2 && component2.count >= 2 &&
                       component1.allSatisfy({ $0.isLetter || $0 == "-" }) &&
                       component2.allSatisfy({ $0.isLetter || $0 == "-" }) {
                        
                        print("✅ Mot composé détecté!")
                        print("🧩 Composant 1: '\(component1)'")
                        print("🧩 Composant 2: '\(component2)'")
                        print("🎯 Pattern utilisé: \(pattern)")
                        
                        return [component1, component2]
                    }
                }
            }
        }
    }
    
    print("⚠️ Aucun mot composé détecté")
    return nil
} }
