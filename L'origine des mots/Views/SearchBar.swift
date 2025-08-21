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
                        .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .overlay(
                        // Ombre interne (effet creusé)
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.black.opacity(0.15), lineWidth: 2)
                            .blur(radius: 3)
                            .offset(x: 0, y: 2)
                            .mask(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(LinearGradient(
                                        colors: [Color.clear, Color.black],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                            )
                    )
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