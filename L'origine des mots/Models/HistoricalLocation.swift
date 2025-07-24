import Foundation
import CoreLocation

struct HistoricalLocation: Identifiable, Codable {
    let id = UUID()
    let coordinates: CLLocationCoordinate2D
    let period: String
    let wordForm: String
    let language: String
    
    init(coordinates: CLLocationCoordinate2D, period: String, wordForm: String, language: String) {
        self.coordinates = coordinates
        self.period = period
        self.wordForm = wordForm
        self.language = language
    }
    
    // Codable conformance pour CLLocationCoordinate2D
    enum CodingKeys: String, CodingKey {
        case coordinates, period, wordForm, language
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        period = try container.decode(String.self, forKey: .period)
        wordForm = try container.decode(String.self, forKey: .wordForm)
        language = try container.decode(String.self, forKey: .language)
        
        let coordData = try container.decode([String: Double].self, forKey: .coordinates)
        coordinates = CLLocationCoordinate2D(
            latitude: coordData["latitude"] ?? 0,
            longitude: coordData["longitude"] ?? 0
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(period, forKey: .period)
        try container.encode(wordForm, forKey: .wordForm)
        try container.encode(language, forKey: .language)
        try container.encode([
            "latitude": coordinates.latitude,
            "longitude": coordinates.longitude
        ], forKey: .coordinates)
    }
} 