import Foundation
import CoreLocation

struct LanguageLocation: Codable, Identifiable {
    let id: UUID
    let language: String
    let latitude: Double
    let longitude: Double
    let city: String
    let period: HistoricalPeriod?
    let abbreviations: [String]?
    let description: String?
    
    var coordinates: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, language, latitude, longitude
        case city = "description"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case abbreviations
        case description = "short_description"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        language = try container.decode(String.self, forKey: .language)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        city = try container.decode(String.self, forKey: .city)
        abbreviations = try container.decodeIfPresent([String].self, forKey: .abbreviations)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        
        if let start = try container.decodeIfPresent(String.self, forKey: .periodStart),
           let end = try container.decodeIfPresent(String.self, forKey: .periodEnd) {
            period = HistoricalPeriod(start: start, end: end)
        } else {
            period = nil
        }
    }
    
    init(id: UUID = UUID(),
         language: String,
         latitude: Double,
         longitude: Double,
         city: String,
         period: HistoricalPeriod? = nil,
         abbreviations: [String]? = nil,
         description: String? = nil) {
        self.id = id
        self.language = language
        self.latitude = latitude
        self.longitude = longitude
        self.city = city
        self.period = period
        self.abbreviations = abbreviations
        self.description = description
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(language, forKey: .language)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(city, forKey: .city)
        try container.encode(period?.start, forKey: .periodStart)
        try container.encode(period?.end, forKey: .periodEnd)
        try container.encode(abbreviations, forKey: .abbreviations)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

struct HistoricalPeriod: Codable {
    let start: String
    let end: String
    
    var description: String {
        "\(start) - \(end)"
    }
}

extension LanguageLocation {
    static let locations: [String: LanguageLocation] = [
        "Français": LanguageLocation(
            language: "Français",
            latitude: 48.8566,
            longitude: 2.3522,
            city: "Paris",
            period: HistoricalPeriod(start: "842", end: "présent"),
            abbreviations: ["fr", "français"],
            description: "La langue officielle de la France"
        ),
        "Latin médiéval": LanguageLocation(
            language: "Latin médiéval",
            latitude: 41.9028,
            longitude: 12.4964,
            city: "Rome",
            period: HistoricalPeriod(start: "IVe siècle", end: "XVe siècle"),
            abbreviations: ["la", "latin"],
            description: "La langue des textes religieux et civils de l'époque"
        ),
        "Arabe": LanguageLocation(
            language: "Arabe",
            latitude: 33.3152,
            longitude: 44.3661,
            city: "Bagdad",
            period: HistoricalPeriod(start: "VIe siècle", end: "présent"),
            abbreviations: ["ar", "arabe"],
            description: "La langue des textes religieux et civils de l'époque"
        ),
        // Ajouter d'autres langues selon les besoins
    ]
}

struct Period: Codable {
    let start: String
    let end: String
}

#if DEBUG
extension LanguageLocation {
    static let previewExample = LanguageLocation(
        language: "Français",
        latitude: 48.8566,
        longitude: 2.3522,
        city: "Paris",
        period: HistoricalPeriod(start: "842", end: "présent"),
        abbreviations: ["fr", "français"],
        description: "La langue officielle de la France"
    )
}
#endif 