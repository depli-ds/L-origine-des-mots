import SwiftUI

struct AppFooterView: View {
    @StateObject private var kilometersCache = KilometersCache.shared
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "location.circle")
                        .foregroundColor(.blue)
                    
                    if kilometersCache.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Calcul en cours...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(formattedKilometers) km")
                            .font(.headline)
                            .fontWeight(.medium)
                        Text("parcourus par les mots")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(spacing: 4) {
                    Text("App créée par")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Link("Dépli design studio", destination: URL(string: "https://depli-ds.com")!)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 40)
        .onAppear {
            loadKilometersStatistic()
        }
    }
    
    private var formattedKilometers: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        let intValue = Int(kilometersCache.totalKilometers)
        return formatter.string(from: NSNumber(value: intValue)) ?? "\(intValue)"
    }
    
    private func loadKilometersStatistic() {
        Task {
            await kilometersCache.loadTotalKilometers()
        }
    }
} 