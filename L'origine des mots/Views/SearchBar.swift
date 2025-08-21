import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    @Binding var isSearching: Bool
    let onSubmit: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
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
                    .shadow(
                        color: colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.1),
                        radius: 15
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