import Foundation

enum CNRTLError: Error {
    case invalidURL
    case networkError
    case serviceUnavailable
    case wordNotFound
    case sectionNotFound
    case maxRedirectsReached
}

/// Accès à l'étymologie TLFi via le Portail lexical (ATILF / CNRS),
/// avec repli temporaire sur l'ancien HTML cnrtl.fr.
class CNRTLService {
    static let shared = CNRTLService()
    
    private let portalBase = "https://www.portail-lexical.fr"
    private let legacyBase = "https://www.cnrtl.fr"
    private let maxRedirects = 3
    
    /// Ordre de préférence quand plusieurs POS sont proposés
    private let preferredPOS = ["nom", "verbe", "adjectif", "adverbe", "interjection"]
    
    private init() {}
    
    // MARK: - API publique (utilisée par EtymologyOrchestrator)
    
    /// Vérifie qu'une entrée existe et renvoie une URL API utilisable pour l'extraction.
    func fetchEtymology(for word: String) async throws -> (String, SourceState) {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        print("\n📚 Vérification Portail lexical pour '\(normalized)'")
        
        if let apiURL = try await resolvePortalAPIURL(for: normalized) {
            print("✅ Entrée Portail lexical trouvée → \(apiURL)")
            return (apiURL, .foundInCNRTL)
        }
        
        // Repli temporaire sur l'ancien portail (jusqu'au cutover du 1er sept. 2026)
        print("⚠️ Portail lexical sans étymologie — repli cnrtl.fr…")
        if let legacyURL = try await resolveLegacyCNRTLURL(for: normalized) {
            print("✅ Page CNRTL legacy trouvée → \(legacyURL)")
            return (legacyURL, .foundInCNRTL)
        }
        
        print("❌ Mot introuvable sur Portail lexical et CNRTL")
        throw CNRTLError.wordNotFound
    }
    
    func fetchEtymologyText(from url: String) async throws -> String {
        if url.contains("portail-lexical.fr") {
            return try await fetchPortalEtymologyText(from: url, redirectCount: 0)
        }
        return try await fetchLegacyEtymologyText(from: url, redirectCount: 0)
    }
    
    /// URL publique pour les écrans « Sources »
    static func publicEtymologyURL(for word: String) -> URL? {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        return URL(string: "https://www.portail-lexical.fr/etymologie/\(encoded)")
    }
    
    // MARK: - Portail lexical (JSON)
    
    private struct PortalSuggestion: Decodable {
        let form: String
        let pos: String
        let label: String?
    }
    
    private struct PortalOther: Decodable {
        let form: String
        let pos: String
        let label: String?
    }
    
    private struct PortalHeader: Decodable {
        let form: String
        let pos: String
        let full_form: String?
        let full_pos: String?
        let others: [PortalOther]?
    }
    
    private struct PortalContentBlock: Decodable {
        let id: String
        // content peut être [String], String, ou objet — on lit en flexible
        let content: FlexibleContent?
    }
    
    private enum FlexibleContent: Decodable {
        case strings([String])
        case string(String)
        case ignored
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let list = try? container.decode([String].self) {
                self = .strings(list)
            } else if let text = try? container.decode(String.self) {
                self = .string(text)
            } else {
                self = .ignored
            }
        }
        
        var joinedHTML: String {
            switch self {
            case .strings(let list): return list.joined(separator: "\n")
            case .string(let text): return text
            case .ignored: return ""
            }
        }
    }
    
    private struct PortalEntry: Decodable {
        let header: PortalHeader?
        let content: [PortalContentBlock]?
        let suggestions: [PortalSuggestion]?
    }
    
    private func resolvePortalAPIURL(for word: String) async throws -> String? {
        let entry = try await fetchPortalEntry(form: word, pos: nil)
        
        if let apiURL = apiURLIfHasEtymology(entry, fallbackForm: word) {
            return apiURL
        }
        
        // Essayer les autres POS listés dans header.others
        if let others = entry.header?.others {
            for other in sortedOthers(others) {
                let alt = try await fetchPortalEntry(form: other.form, pos: other.pos)
                if let apiURL = apiURLIfHasEtymology(alt, fallbackForm: other.form) {
                    print("🔄 Étymologie trouvée via POS alternatif '\(other.pos)'")
                    return apiURL
                }
            }
        }
        
        // Désambiguïsation via suggestions
        if let suggestions = entry.suggestions, !suggestions.isEmpty {
            for suggestion in sortedSuggestions(suggestions) {
                let alt = try await fetchPortalEntry(form: suggestion.form, pos: suggestion.pos)
                if let apiURL = apiURLIfHasEtymology(alt, fallbackForm: suggestion.form) {
                    print("🔄 Étymologie trouvée via suggestion '\(suggestion.label ?? suggestion.form)'")
                    return apiURL
                }
            }
        }
        
        return nil
    }
    
    private func apiURLIfHasEtymology(_ entry: PortalEntry, fallbackForm: String) -> String? {
        guard let header = entry.header,
              etymologyHTML(from: entry) != nil else { return nil }
        return portalAPIURL(form: header.form.isEmpty ? fallbackForm : header.form, pos: header.pos)
    }
    
    private func fetchPortalEtymologyText(from url: String, redirectCount: Int) async throws -> String {
        guard redirectCount < maxRedirects else {
            print("❌ Trop de redirections Portail lexical (max \(maxRedirects))")
            throw CNRTLError.maxRedirectsReached
        }
        
        guard let (form, pos) = parsePortalAPIURL(url) else {
            // URL publique /etymologie/{mot} → résoudre puis extraire
            if let word = parsePortalPublicURL(url) {
                guard let apiURL = try await resolvePortalAPIURL(for: word) else {
                    throw CNRTLError.sectionNotFound
                }
                return try await fetchPortalEtymologyText(from: apiURL, redirectCount: redirectCount)
            }
            throw CNRTLError.invalidURL
        }
        
        let entry = try await fetchPortalEntry(form: form, pos: pos)
        guard let text = etymologyPlainText(from: entry) else {
            print("❌ Bloc etymology absent pour \(form)/\(pos)")
            throw CNRTLError.sectionNotFound
        }
        
        print("🎯 Étymologie Portail lexical extraite (\(text.count) caractères)")
        print("📝 Aperçu: \(String(text.prefix(150)))...")
        
        // Renvois courts du type « Voir X »
        if text.count < 300 && (text.contains("Voir aussi ") || text.hasPrefix("Voir ") || text.hasPrefix("V. ")) {
            if let reference = detectCNRTLReference(in: text) {
                print("🔄 Renvoi détecté vers: \(reference)")
                if let apiURL = try await resolvePortalAPIURL(for: reference.lowercased()) {
                    return try await fetchPortalEtymologyText(from: apiURL, redirectCount: redirectCount + 1)
                }
                // Repli legacy pour les anciennes cibles type "cravate2"
                let legacyURL = "\(legacyBase)/etymologie/\(reference)"
                return try await fetchLegacyEtymologyText(from: legacyURL, redirectCount: redirectCount + 1)
            }
        }
        
        return text
    }
    
    private func fetchPortalEntry(form: String, pos: String?) async throws -> PortalEntry {
        let encodedForm = form.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? form
        var path = "/api/word/\(encodedForm)"
        if let pos, !pos.isEmpty {
            let encodedPOS = pos.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pos
            path += "/\(encodedPOS)"
        }
        
        guard let url = URL(string: portalBase + path) else {
            throw CNRTLError.invalidURL
        }
        
        print("📍 API:", url.absoluteString)
        
        let session = createSession()
        defer { session.invalidateAndCancel() }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CNRTLError.networkError
        }
        
        print("📥 Code HTTP Portail:", httpResponse.statusCode)
        guard httpResponse.statusCode == 200 else {
            throw CNRTLError.networkError
        }
        
        // Décodage tolérant : l'API mélange strings, listes et objets selon les blocs
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CNRTLError.networkError
        }
        return parsePortalEntry(from: root)
    }
    
    private func parsePortalEntry(from root: [String: Any]) -> PortalEntry {
        var header: PortalHeader? = nil
        if let h = root["header"] as? [String: Any],
           let form = h["form"] as? String,
           let pos = h["pos"] as? String {
            let others: [PortalOther]? = (h["others"] as? [[String: Any]])?.compactMap { item in
                guard let f = item["form"] as? String, let p = item["pos"] as? String else { return nil }
                return PortalOther(form: f, pos: p, label: item["label"] as? String)
            }
            header = PortalHeader(
                form: form,
                pos: pos,
                full_form: h["full_form"] as? String,
                full_pos: h["full_pos"] as? String,
                others: others
            )
        }
        
        var content: [PortalContentBlock]? = nil
        if let blocks = root["content"] as? [[String: Any]] {
            content = blocks.compactMap { block in
                guard let id = block["id"] as? String else { return nil }
                let flexible: FlexibleContent
                if let list = block["content"] as? [String] {
                    flexible = .strings(list)
                } else if let text = block["content"] as? String {
                    flexible = .string(text)
                } else {
                    flexible = .ignored
                }
                return PortalContentBlock(id: id, content: flexible)
            }
        }
        
        var suggestions: [PortalSuggestion]? = nil
        if let list = root["suggestions"] as? [[String: Any]] {
            suggestions = list.compactMap { item in
                guard let f = item["form"] as? String, let p = item["pos"] as? String else { return nil }
                return PortalSuggestion(form: f, pos: p, label: item["label"] as? String)
            }
        }
        
        return PortalEntry(header: header, content: content, suggestions: suggestions)
    }
    
    private func etymologyHTML(from entry: PortalEntry) -> String? {
        guard let block = entry.content?.first(where: { $0.id == "etymology" }),
              let content = block.content else { return nil }
        let html = content.joinedHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        return html.count >= 40 ? html : nil
    }
    
    private func etymologyPlainText(from entry: PortalEntry) -> String? {
        guard let html = etymologyHTML(from: entry) else { return nil }
        let cleaned = stripHTML(html)
        return cleaned.count >= 40 ? cleaned : nil
    }
    
    private func portalAPIURL(form: String, pos: String) -> String {
        let encodedForm = form.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? form
        let encodedPOS = pos.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pos
        return "\(portalBase)/api/word/\(encodedForm)/\(encodedPOS)"
    }
    
    private func parsePortalAPIURL(_ url: String) -> (form: String, pos: String)? {
        // .../api/word/{form}/{pos}
        guard let range = url.range(of: "/api/word/") else { return nil }
        let rest = String(url[range.upperBound...])
            .split(separator: "?", maxSplits: 1)[0]
            .split(separator: "#", maxSplits: 1)[0]
        let parts = rest.split(separator: "/").map(String.init)
        guard parts.count >= 2,
              let form = parts[0].removingPercentEncoding,
              let pos = parts[1].removingPercentEncoding else { return nil }
        return (form, pos)
    }
    
    private func parsePortalPublicURL(_ url: String) -> String? {
        guard let range = url.range(of: "/etymologie/") else { return nil }
        let rest = String(url[range.upperBound...])
            .split(separator: "?", maxSplits: 1)[0]
            .split(separator: "#", maxSplits: 1)[0]
            .split(separator: "/", maxSplits: 1)[0]
        return String(rest).removingPercentEncoding?.lowercased()
    }
    
    private func sortedSuggestions(_ suggestions: [PortalSuggestion]) -> [PortalSuggestion] {
        suggestions.sorted { a, b in
            preferredPOSIndex(a.pos) < preferredPOSIndex(b.pos)
        }
    }
    
    private func sortedOthers(_ others: [PortalOther]) -> [PortalOther] {
        others.sorted { a, b in
            preferredPOSIndex(a.pos) < preferredPOSIndex(b.pos)
        }
    }
    
    private func preferredPOSIndex(_ pos: String) -> Int {
        preferredPOS.firstIndex(of: pos.lowercased()) ?? preferredPOS.count
    }
    
    // MARK: - Legacy CNRTL (HTML)
    
    private func resolveLegacyCNRTLURL(for word: String) async throws -> String? {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        let urlString = "\(legacyBase)/etymologie/\(encoded)"
        guard let url = URL(string: urlString) else { return nil }
        
        let session = createSession()
        defer { session.invalidateAndCancel() }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let html = String(data: data, encoding: .utf8),
              !html.contains("Cette forme est introuvable") else {
            return nil
        }
        return urlString
    }
    
    private func fetchLegacyEtymologyText(from url: String, redirectCount: Int) async throws -> String {
        guard redirectCount < maxRedirects else {
            print("❌ Trop de redirections CNRTL legacy (max \(maxRedirects))")
            throw CNRTLError.maxRedirectsReached
        }
        
        guard let url = URL(string: url) else {
            throw CNRTLError.invalidURL
        }
        
        let session = createSession()
        defer { session.invalidateAndCancel() }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw CNRTLError.networkError
        }
        
        print("🏗️ Extraction legacy CNRTL (div#contentbox)")
        
        let quickCheck = stripHTML(html)
        if quickCheck.contains("Cette forme est introuvable") || quickCheck.contains("introuvable") {
            print("❌ Mot introuvable sur CNRTL legacy")
            throw CNRTLError.sectionNotFound
        }
        
        if let contentboxStart = html.range(of: "<div id=\"contentbox\">"),
           let contentboxEnd = html.range(of: "</div></td></tr></table></div>", range: contentboxStart.upperBound..<html.endIndex) {
            
            let contentboxSection = String(html[contentboxStart.upperBound..<contentboxEnd.lowerBound])
            let cleanedEtymology = stripHTML(contentboxSection)
            
            if cleanedEtymology.count >= 100 {
                print("🎯 Section étymologique legacy extraite (\(cleanedEtymology.count) caractères)")
                
                if cleanedEtymology.count < 300 && (cleanedEtymology.contains("Voir aussi ") ||
                   cleanedEtymology.hasPrefix("Voir ") || cleanedEtymology.hasPrefix("V. ")) {
                    if let redirectReference = detectCNRTLReference(in: cleanedEtymology) {
                        print("🔄 Référence legacy vers: \(redirectReference)")
                        if let apiURL = try? await resolvePortalAPIURL(for: redirectReference.lowercased()) {
                            return try await fetchPortalEtymologyText(from: apiURL, redirectCount: redirectCount + 1)
                        }
                        let newUrl = "\(legacyBase)/etymologie/\(redirectReference)"
                        return try await fetchLegacyEtymologyText(from: newUrl, redirectCount: redirectCount + 1)
                    }
                }
                
                return cleanedEtymology
            }
        }
        
        print("⚠️ Extraction structurelle legacy échouée, fallback nettoyage complet")
        
        let cleanedText = html
            .replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
        
        let plain = stripHTML(cleanedText)
        
        if plain.count < 500 || plain.contains("Voir ") || plain.contains("V. ") {
            if let redirectReference = detectCNRTLReference(in: plain) {
                print("🔄 Référence détectée vers: \(redirectReference)")
                let newUrl = "\(legacyBase)/etymologie/\(redirectReference)"
                return try await fetchLegacyEtymologyText(from: newUrl, redirectCount: redirectCount + 1)
            }
        }
        
        if plain.count < 100 {
            print("❌ Page CNRTL legacy trop courte ou vide")
            throw CNRTLError.sectionNotFound
        }
        
        return plain
    }
    
    // MARK: - Utilitaires
    
    private func stripHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func detectCNRTLReference(in text: String) -> String? {
        let referencePatterns = [
            "Voir\\s+aussi\\s+([a-zA-ZÀ-ÿ0-9]+)",
            "Voir\\s+([a-zA-ZÀ-ÿ0-9]+)",
            "V\\.\\s+([a-zA-ZÀ-ÿ0-9]+)",
            "Cf\\.\\s+([a-zA-ZÀ-ÿ0-9]+)",
            "([a-zA-ZÀ-ÿ]+\\d+)"
        ]
        
        for pattern in referencePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsText = text as NSString
                let results = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
                
                if let result = results.first, result.numberOfRanges > 1 {
                    let referenceRange = result.range(at: 1)
                    if referenceRange.location != NSNotFound {
                        let reference = nsText.substring(with: referenceRange)
                        print("🎯 Référence extraite: '\(reference)'")
                        return reference
                    }
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
    
    func detectComposedWord(in etymologyText: String) -> [String]? {
        print("🔍 Analyse du texte pour détecter un mot composé...")
        print("📝 Texte analysé: \(String(etymologyText.prefix(200)))...")
        
        let composedPatterns = [
            "Composé de l'élément préf\\. ([a-zA-ZÀ-ÿ-]+).*?et de ([a-zA-ZÀ-ÿ-]+)",
            "Composé de ([a-zA-ZÀ-ÿ-]+) et (?:de )?([a-zA-ZÀ-ÿ-]+)",
            "formé de ([a-zA-ZÀ-ÿ-]+) et (?:de )?([a-zA-ZÀ-ÿ-]+)",
            "Dérivé de ([a-zA-ZÀ-ÿ-]+) et (?:de )?([a-zA-ZÀ-ÿ-]+)",
            "de ([a-zA-ZÀ-ÿ-]+) \\+ ([a-zA-ZÀ-ÿ-]+)",
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
                        
                        if component1.count >= 2 && component2.count >= 2 &&
                           component1.allSatisfy({ $0.isLetter || $0 == "-" }) &&
                           component2.allSatisfy({ $0.isLetter || $0 == "-" }) {
                            
                            print("✅ Mot composé détecté!")
                            print("🧩 Composant 1: '\(component1)'")
                            print("🧩 Composant 2: '\(component2)'")
                            return [component1, component2]
                        }
                    }
                }
            }
        }
        
        print("⚠️ Aucun mot composé détecté")
        return nil
    }
}
