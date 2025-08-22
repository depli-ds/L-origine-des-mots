//
//  L_origine_des_motsApp.swift
//  L'origine des mots
//
//  Created by Vadim Bernard on 15/11/2024.
//

import SwiftUI

@main
struct L_origine_des_motsApp: App {
    @State private var isAppReady = false
    @State private var isInitializing = true
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isInitializing {
                    SplashScreenView()
                        .transition(.opacity)
                } else {
                    ContentView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: isInitializing)
            .preferredColorScheme(nil)
            .statusBarHidden(true)  // Configuration globale
            .onAppear {
                initializeApp()
            }
        }
    }
    
    private func initializeApp() {
        Task {
            // Démarrer les tâches d'initialisation en parallèle
            async let cacheInitialization: Void = initializeCaches()
            async let dataPreloading: Void = preloadData()
            
            // Attendre que toutes les tâches soient terminées
            _ = await (cacheInitialization, dataPreloading)
            
            // Attendre un minimum pour que l'utilisateur voie le logo
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 secondes
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isInitializing = false
                    isAppReady = true
                }
            }
        }
    }
    
    private func initializeCaches() async {
        // Initialiser les caches si nécessaire
        // SupabaseService.shared.clearAllCaches() // Optionnel
        
        // Charger les kilomètres totaux dans le cache
        await KilometersCache.shared.loadTotalKilometers()
        
        print("✅ Caches initialisés")
    }
    
    private func preloadData() async {
        do {
            // Pré-charger le total des kilomètres en arrière-plan
            _ = try await SupabaseService.shared.getTotalKilometers()
            
            // Pré-charger les mots remarquables pour éviter le double loading
            _ = try await SupabaseService.shared.fetchRemarkableWords()
            
            print("✅ Données pré-chargées")
        } catch {
            print("⚠️ Erreur lors du pré-chargement: \(error)")
            // L'erreur n'empêche pas l'application de démarrer
        }
    }
} 