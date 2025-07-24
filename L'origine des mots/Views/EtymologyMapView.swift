import SwiftUI
import MapKit

struct EtymologyMapView: View {
    let word: Word
    @Environment(\.dismiss) private var dismiss
    @State private var historicalLocations: [HistoricalLocation] = []
    @State private var isLoading = true
    @State private var cameraPosition: MapCameraPosition = .camera(MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 45.0, longitude: 10.0),
        distance: 10000000,
        heading: 0,
        pitch: 60
    ))
    
    init(word: Word) {
        self.word = word
    }
    
    var coordinates: [CLLocationCoordinate2D] {
        historicalLocations.map(\.coordinates)
    }
    
    // Pointillés avec taille constante à l'écran
    private var constantDashPattern: [CGFloat] {
        // Valeurs fixes optimisées pour une apparence constante
        return [12, 8]
    }
    
    private var constantLineWidth: CGFloat {
        // Épaisseur fixe optimisée
        return 3.0
    }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Chargement de la carte...")
            } else if historicalLocations.isEmpty {
                VStack {
                    Image(systemName: "map")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("Aucune localisation disponible")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Text("Ajoutez les langues manquantes pour voir la route")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .overlay(alignment: .topTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.gray)
                    }
                    .padding()
                }
            } else {
                Map(position: $cameraPosition) {
                    ForEach(historicalLocations.indices, id: \.self) { index in
                        let location = historicalLocations[index]
                        
                        Annotation("", coordinate: location.coordinates) {
                            VStack(spacing: 2) {
                                // Mot principal en haut
                                Text(location.wordForm)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black, radius: 2)
                                
                                // Espacement réduit pour le point blanc
                                Spacer()
                                    .frame(height: 8)
                                
                                // Informations en bas
                                VStack(spacing: 2) {
                                    Text(location.period)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                        .shadow(color: .black, radius: 1)
                                    
                                    Text(location.language)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.white.opacity(0.8))
                                        .shadow(color: .black, radius: 1)
                                }
                                .offset(y: 12)
                            }
                            .overlay(
                                // Point séparateur agrandi de 50% (8x8 -> 12x12)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 12, height: 12)
                                    .overlay(
                                        Circle()
                                            .stroke(.white, lineWidth: 1)
                                    )
                            )
                        }
                    }
                    
                    // Ligne pointillée reliant les locations avec taille constante
                    if historicalLocations.count > 1 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(.white, style: StrokeStyle(
                                lineWidth: constantLineWidth,
                                dash: constantDashPattern
                            ))
                    }
                }
                .mapStyle(.imagery(elevation: .realistic))
                .preferredColorScheme(.dark)
                .navigationBarHidden(true)
                .overlay(alignment: .top) {
                    // En-tête avec titre centré et bouton de fermeture
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("Voyage du mot :")
                                .font(.system(size: 16, weight: .light))
                                .foregroundColor(.white.opacity(0.9))
                                .shadow(color: .black, radius: 2)
                            Text(word.word)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 2)
                        }
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 2)
                        }
                        .padding(.leading, -40)
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                }
            }
        }
        .task {
            await loadLocations()
        }
    }
    
    private func loadLocations() async {
        do {
            print("🗺 Chargement des locations temporaires...")
            // Si le mot a explicitement une distance nulle (shortDescription = "0"), ne pas essayer de charger les locations
            if word.shortDescription == "0" {
                print("ℹ️ Mot sans déplacement géographique, affichage de la vue vide")
                historicalLocations = []
                isLoading = false
                return
            }
            
            let allLocations = try await word.temporaryLocations()
            
            // Filtrer les locations avec des coordonnées valides
            let validLocations = allLocations.filter { location in
                let coord = location.coordinates
                let isValid = !coord.latitude.isNaN && !coord.longitude.isNaN &&
                             coord.latitude.isFinite && coord.longitude.isFinite &&
                             coord.latitude >= -90 && coord.latitude <= 90 &&
                             coord.longitude >= -180 && coord.longitude <= 180
                
                if !isValid {
                    print("⚠️ Coordonnées invalides filtrées pour \(location.language): lat=\(coord.latitude), lon=\(coord.longitude)")
                }
                
                return isValid
            }
            
            // Filtrer les doublons géographiques en gardant le plus ancien
            historicalLocations = filterOldestByLocation(validLocations)
            
            print("✅ \(historicalLocations.count) locations temporaires valides chargées (après filtrage des doublons)")
            
            if !historicalLocations.isEmpty {
                let coordinates = historicalLocations.map(\.coordinates)
                let region = calculateRegion(for: coordinates)
                
                // Animation de dezoom
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .camera(MapCamera(
                        centerCoordinate: region.center,
                        distance: max(region.span.latitudeDelta, region.span.longitudeDelta) * 200000,
                        heading: 0,
                        pitch: 60
                    ))
                }
            }
            isLoading = false
        } catch {
            print("❌ Erreur de chargement des locations temporaires:", error)
            isLoading = false
        }
    }
    
    // Fonction pour filtrer les doublons géographiques en gardant le plus ancien
    private func filterOldestByLocation(_ locations: [HistoricalLocation]) -> [HistoricalLocation] {
        // Grouper par coordonnées (avec tolérance pour les coordonnées très proches)
        let tolerance = 0.001 // ~100m de tolérance
        var locationGroups: [[HistoricalLocation]] = []
        
        for location in locations {
            // Chercher un groupe existant avec des coordonnées similaires
            var addedToGroup = false
            for i in 0..<locationGroups.count {
                let groupRepresentative = locationGroups[i].first!
                let latDiff = abs(location.coordinates.latitude - groupRepresentative.coordinates.latitude)
                let lonDiff = abs(location.coordinates.longitude - groupRepresentative.coordinates.longitude)
                
                if latDiff < tolerance && lonDiff < tolerance {
                    locationGroups[i].append(location)
                    addedToGroup = true
                    break
                }
            }
            
            // Si pas trouvé de groupe similaire, créer un nouveau groupe
            if !addedToGroup {
                locationGroups.append([location])
            }
        }
        
        // Pour chaque groupe, garder seulement le plus ancien
        var filteredLocations: [HistoricalLocation] = []
        
        for group in locationGroups {
            if group.count == 1 {
                // Pas de doublon, garder tel quel
                filteredLocations.append(group.first!)
            } else {
                // Plusieurs locations au même endroit, garder la plus ancienne
                let oldest = findOldestLocation(in: group)
                filteredLocations.append(oldest)
                
                print("📍 Doublons détectés à (\(oldest.coordinates.latitude), \(oldest.coordinates.longitude))")
                print("   🏆 Gardé: \(oldest.language) - \(oldest.period) (\(oldest.wordForm))")
                for otherLocation in group where otherLocation.id != oldest.id {
                    print("   ❌ Filtré: \(otherLocation.language) - \(otherLocation.period) (\(otherLocation.wordForm))")
                }
            }
        }
        
        return filteredLocations
    }
    
    // Fonction pour trouver le location le plus ancien dans un groupe
    private func findOldestLocation(in locations: [HistoricalLocation]) -> HistoricalLocation {
        // Convertir les périodes en valeurs numériques pour la comparaison
        func extractYear(from period: String) -> Int {
            // Nettoyer et extraire les années
            let cleaned = period.lowercased()
                .replacingOccurrences(of: "av. j.-c.", with: "")
                .replacingOccurrences(of: "avant j.-c.", with: "")
                .replacingOccurrences(of: "après j.-c.", with: "")
                .replacingOccurrences(of: "j.-c.", with: "")
                .replacingOccurrences(of: "siècle", with: "")
                .replacingOccurrences(of: "ème", with: "")
                .replacingOccurrences(of: "er", with: "")
                .replacingOccurrences(of: "ième", with: "")
                .replacingOccurrences(of: "présent", with: "2024")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Chercher des nombres romains
            let romanToArabic: [String: Int] = [
                "i": 1, "ii": 2, "iii": 3, "iv": 4, "v": 5,
                "vi": 6, "vii": 7, "viii": 8, "ix": 9, "x": 10,
                "xi": 11, "xii": 12, "xiii": 13, "xiv": 14, "xv": 15,
                "xvi": 16, "xvii": 17, "xviii": 18, "xix": 19, "xx": 20,
                "xxi": 21
            ]
            
            for (roman, arabic) in romanToArabic {
                if cleaned.contains(roman) {
                    let year = arabic * 100 // Convertir siècle en année approximative
                    // Si c'est avant J.-C., rendre négatif
                    return period.lowercased().contains("av") ? -year : year
                }
            }
            
            // Chercher des nombres arabes
            let numbers = cleaned.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .filter { $0 > 0 }
            
            if let firstNumber = numbers.first {
                // Si c'est un siècle (nombre < 30), le convertir
                let year = firstNumber < 30 ? firstNumber * 100 : firstNumber
                // Si c'est avant J.-C., rendre négatif
                return period.lowercased().contains("av") ? -year : year
            }
            
            // Par défaut, retourner 0 (période inconnue)
            return 0
        }
        
        // Trier par année (plus petit = plus ancien)
        let sortedLocations = locations.sorted { location1, location2 in
            let year1 = extractYear(from: location1.period)
            let year2 = extractYear(from: location2.period)
            return year1 < year2
        }
        
        return sortedLocations.first!
    }
    
    private func calculateRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        // Filtrer les coordonnées invalides
        let validCoordinates = coordinates.filter { coordinate in
            !coordinate.latitude.isNaN && !coordinate.longitude.isNaN &&
            coordinate.latitude.isFinite && coordinate.longitude.isFinite &&
            coordinate.latitude >= -90 && coordinate.latitude <= 90 &&
            coordinate.longitude >= -180 && coordinate.longitude <= 180
        }
        
        guard !validCoordinates.isEmpty else {
            // Retourner une région par défaut si aucune coordonnée valide
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.0, longitude: 10.0),
                span: MKCoordinateSpan(latitudeDelta: 50.0, longitudeDelta: 50.0)
            )
        }
        
        let minLat = validCoordinates.map(\.latitude).min() ?? 0
        let maxLat = validCoordinates.map(\.latitude).max() ?? 0
        let minLon = validCoordinates.map(\.longitude).min() ?? 0
        let maxLon = validCoordinates.map(\.longitude).max() ?? 0
        
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let deltaLat = max((maxLat - minLat) * 2.0, 1.0) // Minimum 1 degré
        let deltaLon = max((maxLon - minLon) * 2.0, 1.0) // Minimum 1 degré
        
        // Vérifier que les valeurs calculées sont valides
        guard !centerLat.isNaN && !centerLon.isNaN && 
              !deltaLat.isNaN && !deltaLon.isNaN &&
              centerLat.isFinite && centerLon.isFinite &&
              deltaLat.isFinite && deltaLon.isFinite else {
            // Retourner une région par défaut en cas de calcul invalide
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.0, longitude: 10.0),
                span: MKCoordinateSpan(latitudeDelta: 50.0, longitudeDelta: 50.0)
            )
        }
        
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: deltaLat, longitudeDelta: deltaLon)
        )
    }
}

// Extension pour convertir les coordonnées en points
extension CLLocationCoordinate2D {
    func toPoint(in region: MKCoordinateRegion) -> CGPoint {
        let latRatio = (latitude - region.center.latitude) / region.span.latitudeDelta
        let lonRatio = (longitude - region.center.longitude) / region.span.longitudeDelta
        return CGPoint(x: lonRatio * 500 + 250, y: -latRatio * 500 + 250)
    }
}

struct MapView: View {
    let locations: [LanguageLocation]
    
    var body: some View {
        Map {
            ForEach(locations) { location in
                Marker(
                    location.language,
                    coordinate: location.coordinates
                )
            }
        }
    }
}

#Preview {
    EtymologyMapView(word: Word.previewExample)
} 

