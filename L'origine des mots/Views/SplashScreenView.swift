import SwiftUI

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            // Arrière-plan
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                // Contenu principal centré optiquement
                VStack(spacing: 20) {
                    // Globe centré à 200% en light
                    Image(systemName: "globe")
                        .font(.system(size: 100, weight: .light))
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 8) {
                        // Titre dans le même style que l'app
                        Text("L'origine des mots")
                            .font(.title)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        // Version sous le titre en petit
                        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                            Text("Version \(version) (\(build))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                    .frame(height: 200)
                
                // Footer avec les mêmes infos que AppFooterView
                VStack(spacing: 8) {
                    Text("App créée par")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Dépli design studio")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                .padding(.bottom, 30)
            }
        }
    }
}

#Preview {
    SplashScreenView()
} 