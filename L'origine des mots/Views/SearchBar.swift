import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    @Binding var isSearching: Bool
    let onSubmit: () -> Void
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("Rechercher un mot...", text: $text)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit(onSubmit)
                
                if !text.isEmpty {
                    Button(action: {
                        text = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .overlay(
                        // Ombre interne subtile
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            .blur(radius: 0.5)
                            .offset(x: 0, y: 0.5)
                            .mask(RoundedRectangle(cornerRadius: 12))
                    )
                    .overlay(
                        // Liseret extérieur
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
            )
            
            if isSearching {
                Button("Annuler") {
                    text = ""
                    isSearching = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                 to: nil, from: nil, for: nil)
                }
                .transition(.move(edge: .trailing))
            }
        }
        .padding(.horizontal)
        .animation(.default, value: isSearching)
    }
}

#Preview {
    SearchBar(
        text: .constant(""),
        isSearching: .constant(false),
        onSubmit: {}
    )
} 