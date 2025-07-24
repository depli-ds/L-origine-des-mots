import Foundation
import CoreLocation

enum LanguageAnalysisType: String, Codable {
    case newLanguage = "NEW_LANGUAGE"
    case newAbbreviation = "NEW_ABBREVIATION"
    case known = "KNOWN"
}

struct LanguageAnalysis: Codable {
    let type: String
    let name: String
    let abbreviations: [String]
    let latitude: Double
    let longitude: Double
    let description: String
    let periodStart: String
    let periodEnd: String
    let shortDescription: String?
    let justification: String
    let existingLanguage: String?
    
    enum CodingKeys: String, CodingKey {
        case type, name, abbreviations, latitude, longitude, description
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case shortDescription = "short_description"
        case justification
        case existingLanguage = "existing_language"
    }
    
    init(type: LanguageAnalysisType, 
         name: String,
         abbreviations: [String] = [],
         latitude: Double,
         longitude: Double,
         description: String,
         periodStart: String,
         periodEnd: String,
         justification: String,
         shortDescription: String? = nil,
         existingLanguage: String? = nil) {
        
        self.type = type.rawValue
        self.name = name.trimmingCharacters(in: .whitespaces)
        self.abbreviations = abbreviations.map { $0.trimmingCharacters(in: .whitespaces) }
        self.latitude = latitude
        self.longitude = longitude
        self.description = description.trimmingCharacters(in: .whitespaces)
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.shortDescription = shortDescription?.trimmingCharacters(in: .whitespaces)
        self.justification = justification.trimmingCharacters(in: .whitespaces)
        self.existingLanguage = existingLanguage?.trimmingCharacters(in: .whitespaces)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(abbreviations, forKey: .abbreviations)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(description, forKey: .description)
        try container.encode(periodStart, forKey: .periodStart)
        try container.encode(periodEnd, forKey: .periodEnd)
        try container.encode(justification, forKey: .justification)
        try container.encodeIfPresent(shortDescription, forKey: .shortDescription)
        try container.encodeIfPresent(existingLanguage, forKey: .existingLanguage)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        abbreviations = try container.decode([String].self, forKey: .abbreviations)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        description = try container.decode(String.self, forKey: .description)
        periodStart = try container.decode(String.self, forKey: .periodStart)
        periodEnd = try container.decode(String.self, forKey: .periodEnd)
        justification = try container.decode(String.self, forKey: .justification)
        shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        existingLanguage = try container.decodeIfPresent(String.self, forKey: .existingLanguage)
    }
}

struct HistoricalLanguage: Codable {
    let language: String
    let city: String
    let coordinates: Coordinates
    let period: String
    let justification: String
    
    init(language: String, city: String, latitude: Double, longitude: Double, period: String, justification: String) {
        self.language = language.trimmingCharacters(in: .whitespaces)
        self.city = city.trimmingCharacters(in: .whitespaces)
        self.coordinates = Coordinates(latitude: latitude, longitude: longitude)
        self.period = period.trimmingCharacters(in: .whitespaces)
        self.justification = justification.trimmingCharacters(in: .whitespaces)
    }
    
    enum CodingKeys: String, CodingKey {
        case language, city, coordinates, justification
        case period = "historical_period"
    }
} 