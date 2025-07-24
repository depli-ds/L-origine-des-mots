import Foundation

class TextPreprocessor {
    private let knownLanguages: [String]
    
    init(knownLanguages: [String]) {
        self.knownLanguages = knownLanguages.map { $0.lowercased() }
        print("\n🔍 Initialisation du TextPreprocessor")
        print("📚 Langues connues:", knownLanguages.joined(separator: ", "))
    }
    
    func preprocessEtymology(_ text: String) -> PreprocessingResult {
        print("\n🔄 Prétraitement du texte")
        print("📝 Texte d'entrée (\(text.count) caractères)")
        
        // 1. Extraire la première attestation
        let firstAttestation = extractFirstAttestation(from: text)
        print("📅 Première attestation:", firstAttestation)
        
        // 2. Extraire la chaîne étymologique
        let etymologyChain = extractEtymologyChain(from: text)
        print("🔗 Chaîne étymologique:", etymologyChain)
        
        // 3. Extraire les mots sources
        let sourceWords = extractSourceWords(from: text)
        print("📖 Mots sources:", sourceWords.joined(separator: ", "))
        
        // 4. Identifier les langues inconnues
        let unknownLanguages = findUnknownLanguages(in: etymologyChain)
        if !unknownLanguages.isEmpty {
            print("⚠️ Langues inconnues:", unknownLanguages.joined(separator: ", "))
        }
        
        // 5. Créer le résultat
        let etymology = PreprocessedEtymology(
            etymologyChain: etymologyChain,
            sourceWords: sourceWords,
            firstAttestation: firstAttestation
        )
        
        print("✅ Prétraitement terminé")
        return PreprocessingResult(
            etymology: etymology
        )
    }
    
    private func extractFirstAttestation(from text: String) -> String {
        // Motifs pour trouver la première attestation
        let patterns = [
            #"(\d{4})[^\d]*?(?:attesté|emprunté|attestation)"#,
            #"(?:attesté|emprunté|attestation)[^\d]*?(\d{4})"#,
            #"(\d{4})"#
        ]
        
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let match = text[range]
                print("✅ Attestation trouvée avec pattern:", pattern)
                return String(match)
            }
        }
        
        print("⚠️ Aucune attestation trouvée")
        return "Date inconnue"
    }
    
    private func extractEtymologyChain(from text: String) -> String {
        // Nettoyer et normaliser le texte
        var cleanText = text
            .replacingOccurrences(of: #"[\n\r\t]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remplacer les variantes de flèches et tirets par →
        let arrowPatterns = [
            " > ", " → ", " ⟶ ", " ⟹ ", " ⇒ ", " => ",
            " - ", " -- ", " — ", " – ", " − "
        ]
        
        for pattern in arrowPatterns {
            cleanText = cleanText.replacingOccurrences(of: pattern, with: " → ")
        }
        
        print("🧹 Texte nettoyé:", cleanText)
        return cleanText
    }
    
    private func extractSourceWords(from text: String) -> [String] {
        // Extraire les mots entre guillemets ou en italique
        let patterns = [
            "«([^»]+)»",
            "_([^_]+)_",
            "\\*([^\\*]+)\\*"
        ]
        
        var words: [String] = []
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, range: range)
                
                for match in matches {
                    if let range = Range(match.range(at: 1), in: text) {
                        words.append(String(text[range]))
                    }
                }
            }
        }
        
        // Nettoyer les mots trouvés
        return words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func findUnknownLanguages(in text: String) -> [String] {
        // Extraire les noms de langues potentiels
        let languagePattern = "[A-Z][a-zÀ-ÿ]+"
        
        if let regex = try? NSRegularExpression(pattern: languagePattern) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            
            let potentialLanguages = matches.compactMap { match -> String? in
                guard let range = Range(match.range, in: text) else { return nil }
                return String(text[range]).lowercased()
            }
            .filter { !knownLanguages.contains($0) }
            
            return Array(Set(potentialLanguages))
        }
        
        return []
    }
    
    func normalizeLanguageName(_ detected: String) -> String? {
        // Map temporaire des abréviations courantes
        let abbreviationMap = [
            "angl": "Anglais",
            "lang. indigène d'Australie": "Langue aborigène d'Australie",
            "langue indigène d'Australie": "Langue aborigène d'Australie",
            "indigène d'Australie": "Langue aborigène d'Australie"
        ]
        
        // Vérifier d'abord dans les langues connues
        if knownLanguages.contains(detected) {
            return detected
        }
        
        // Puis vérifier les abréviations
        return abbreviationMap[detected.lowercased()]
    }
    
    private func extractLanguageFromMatch(_ match: NSTextCheckingResult, in text: String) -> String? {
        if let range = Range(match.range(at: 1), in: text) {
            return String(text[range])
        }
        return nil
    }
} 