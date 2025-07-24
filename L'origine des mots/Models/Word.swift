import Foundation

struct Word: Codable {
    let id: String
    let word: String
    let etymology: DirectEtymology
    let language: String
    let source: String
    let createdAt: Date
    let updatedAt: Date
    let foundInCNRTL: Bool
    let foundWithCNRTLAndClaude: Bool?
    let isRemarkable: Bool
    let shortDescription: String?
    let distanceKm: Double?
    let isComposedWord: Bool
    let components: [String]
    let gptAnalysis: EtymologyAnalysis?

    enum CodingKeys: String, CodingKey {
        case id
        case word
        case etymology
        case language
        case source
        case createdAt
        case updatedAt
        case foundInCNRTL
        case foundWithCNRTLAndClaude
        case isRemarkable
        case shortDescription
        case distanceKm
        case isComposedWord
        case components
        case gptAnalysis
    }
}

extension Word {
    static let previewExample = Word(
        id: "example-id",
        word: "exemple",
        etymology: DirectEtymology(chain: []),
        language: "français",
        source: "CNRTL",
        createdAt: Date(),
        updatedAt: Date(),
        foundInCNRTL: true,
        foundWithCNRTLAndClaude: true,
        isRemarkable: false,
        shortDescription: nil,
        distanceKm: nil,
        isComposedWord: false,
        components: [],
        gptAnalysis: nil
    )

    var hasGeographicalJourney: Bool {
        let uniqueLanguages = Set(etymology.chain.map { $0.language })
        let hasValidDistance = (distanceKm ?? 0) > 0
        return uniqueLanguages.count > 1 && hasValidDistance
    }
    
    var hasGeographicalJourney_OLD: Bool {
        let uniqueLanguages = Set(etymology.chain.map { $0.language })
        return uniqueLanguages.count > 1
    }

    func calculateEtymologicalDistance() async throws -> Double {
        var totalDistance: Double = 0
        
        // Vérifier qu'il y a au moins 2 entrées pour calculer une distance
        guard etymology.chain.count > 1 else {
            print("⚠️ Étymologie trop courte (\(etymology.chain.count) entrée(s)) - distance = 0")
            return 0.0
        }
        
        for i in 0..<etymology.chain.count - 1 {
            let currentEntry = etymology.chain[i]
            let nextEntry = etymology.chain[i + 1]
            
            guard let currentLocation = try await SupabaseService.shared.getLocation(for: currentEntry.language),
                  let nextLocation = try await SupabaseService.shared.getLocation(for: nextEntry.language) else {
                print("⚠️ Localisation manquante pour \(currentEntry.language) ou \(nextEntry.language)")
                continue
            }
            
            let distance = calculateDistance(from: currentLocation, to: nextLocation)
            totalDistance += distance
            
            print("📏 \(currentEntry.language) → \(nextEntry.language): \(String(format: "%.1f", distance)) km")
        }
        
        return totalDistance
    }
    
    private func calculateDistance(from location1: LanguageLocation, to location2: LanguageLocation) -> Double {
        let coord1 = location1.coordinates
        let coord2 = location2.coordinates
        
        let deltaLat = (coord2.latitude - coord1.latitude) * .pi / 180
        let deltaLon = (coord2.longitude - coord1.longitude) * .pi / 180
        
        let a = sin(deltaLat/2) * sin(deltaLat/2) +
                cos(coord1.latitude * .pi / 180) * cos(coord2.latitude * .pi / 180) *
                sin(deltaLon/2) * sin(deltaLon/2)
        
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        let earthRadius = 6371.0
        
        return earthRadius * c
    }
    
    func calculateEtymologicalDistance_OLD() async throws -> Double {
        return 0.0
    }

    func temporaryLocations() async throws -> [HistoricalLocation] {
        var locations: [HistoricalLocation] = []

        for entry in etymology.chain {
            if let languageLocation = try await SupabaseService.shared.getLocation(for: entry.language) {
                let historicalLocation = HistoricalLocation(
                    coordinates: languageLocation.coordinates,
                    period: entry.period ?? "Période inconnue",
                    wordForm: entry.sourceWord,
                    language: entry.language
                )
                locations.append(historicalLocation)
            } else {
                print("⚠️ Aucune localisation trouvée pour la langue: \(entry.language)")
            }
        }

        return locations
    }
}
