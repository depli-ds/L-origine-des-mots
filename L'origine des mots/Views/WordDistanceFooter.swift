import SwiftUI

struct WordDistanceFooter: View {
    let word: Word
    @State private var calculatedDistance: Double = 0.0
    @State private var isCalculating = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Utiliser directement la distance stockée dans le mot
            if let distance = word.distanceKm, distance > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "map.circle")
                        .foregroundColor(.blue)
                    Text(formatDistance(distance))
                        .font(.headline)
                        .fontWeight(.medium)
                    Text("parcourus par ce mot")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 16)
            }
            // Sinon, calculer en temps réel et afficher
            else if calculatedDistance > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "map.circle")
                        .foregroundColor(.orange) // Couleur différente pour indiquer calcul temps réel
                    Text(formatDistance(calculatedDistance))
                        .font(.headline)
                        .fontWeight(.medium)
                    Text("parcourus par ce mot (calculé)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 16)
            }
            // Affichage pendant le calcul
            else if isCalculating {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Calcul de la distance...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            calculateDistanceIfNeeded()
        }
    }
    
    private func calculateDistanceIfNeeded() {
        // Si la distance n'est pas stockée et qu'on a une chaîne étymologique
        if word.distanceKm == nil && word.etymology.chain.count > 1 {
            isCalculating = true
            
            Task {
                do {
                    let distance = try await word.calculateEtymologicalDistance()
                    await MainActor.run {
                        calculatedDistance = distance
                        isCalculating = false
                        print("💡 Distance calculée en temps réel pour '\(word.word)': \(distance) km")
                    }
                } catch {
                    await MainActor.run {
                        isCalculating = false
                        print("❌ Erreur calcul distance pour '\(word.word)': \(error)")
                    }
                }
            }
        }
    }
    
    // Fonction pour formater la distance
    static func formatDistance(_ distance: Double) -> String {
        if distance < 1.0 {
            return String(format: "%.0f m", distance * 1000)
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = " "
            let intValue = Int(distance)
            return (formatter.string(from: NSNumber(value: intValue)) ?? "\(intValue)") + " km"
        }
    }
    
    private func formatDistance(_ distance: Double) -> String {
        return Self.formatDistance(distance)
    }
} 