import Foundation

struct Coordinates: Codable {
    let latitude: Double
    let longitude: Double
    
    init(latitude: Double, longitude: Double) {
        // Validation basique
        self.latitude = max(-90, min(90, latitude))
        self.longitude = max(-180, min(180, longitude))
    }
} 