import SwiftUI

struct AppHeaderView: View {
    var body: some View {
        HStack {
            Spacer()
            Text("L'origine des mots")
                .font(.system(size: 36, weight: .medium))
            Image(systemName: "globe")
                .font(.system(size: 24, weight: .medium))
                .padding(.leading, 8)
            Spacer()
        }
        .padding(.top, 30)
        .padding(.bottom, 20)
        .background(Color(.systemBackground))
    }
}

#Preview {
    AppHeaderView()
} 
