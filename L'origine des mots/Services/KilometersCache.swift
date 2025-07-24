import Foundation
import Combine
import SwiftUI

@MainActor
class KilometersCache: ObservableObject {
    static let shared = KilometersCache()
    
    @Published var totalKilometers: Double = 0.0
    @Published var isLoading: Bool = false
    
    private var cachedTotal: Double?
    private var lastCacheUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    /// Charge le total des kilomètres (avec cache intelligent)
    func loadTotalKilometers() async {
        // Vérifier si le cache est encore valide
        if let cached = cachedTotal,
           let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheValidityDuration {
            print("📦 Utilisation du cache kilomètres : \(cached) km")
            totalKilometers = cached
            return
        }
        
        // Charger depuis la base
        await refreshFromDatabase()
    }
    
    /// Force le rechargement depuis la base de données
    func refreshFromDatabase() async {
        isLoading = true
        
        do {
            let realTotal = try await SupabaseService.shared.getTotalKilometers()
            
            // Mise à jour du cache et de la valeur publiée
            cachedTotal = realTotal
            lastCacheUpdate = Date()
            
            withAnimation(.easeInOut(duration: 0.8)) {
                totalKilometers = realTotal
            }
            
            print("🔄 Cache kilomètres mis à jour : \(realTotal) km")
            
        } catch {
            print("❌ Erreur lors du chargement des kilomètres : \(error)")
            // Garder la valeur en cache en cas d'erreur
        }
        
        isLoading = false
    }
    
    /// Force une synchronisation complète avec la base de données
    func forceSyncWithDatabase() async {
        print("🔄 Synchronisation forcée avec la base de données...")
        // Invalider le cache
        invalidateCache()
        // Recharger depuis la base avec reset visuel
        totalKilometers = 0.0
        await refreshFromDatabase()
    }
    
    /// Ajoute des kilomètres au cache local (mise à jour optimiste)
    func addKilometers(_ distance: Double) {
        // Ne pas faire de mise à jour optimiste si on n'a pas encore de total de base
        guard let currentCached = cachedTotal else {
            print("⚠️ Pas de total en cache, skip de la mise à jour optimiste")
            return
        }
        
        let newTotal = currentCached + distance
        
        // Mise à jour optimiste du cache
        cachedTotal = newTotal
        lastCacheUpdate = Date()
        
        withAnimation(.easeInOut(duration: 0.6)) {
            totalKilometers = newTotal
        }
        
        print("➕ Cache kilomètres mis à jour (optimiste) : +\(String(format: "%.1f", distance)) km → Total: \(String(format: "%.1f", newTotal)) km")
    }
    
    /// Invalide le cache pour forcer un rechargement
    func invalidateCache() {
        cachedTotal = nil
        lastCacheUpdate = nil
        print("🗑️ Cache kilomètres invalidé")
    }
} 