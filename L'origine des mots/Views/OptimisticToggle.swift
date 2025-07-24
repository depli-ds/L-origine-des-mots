import SwiftUI

struct OptimisticToggle: View {
    let onToggle: (Bool) -> Void
    
    @State private var localValue: Bool
    @State private var isUpdating = false
    
    init(initialValue: Bool, onToggle: @escaping (Bool) -> Void) {
        self._localValue = State(initialValue: initialValue)
        self.onToggle = onToggle
    }
    
    var body: some View {
        HStack {
            if isUpdating {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 44, height: 28)
            } else {
                Toggle("", isOn: Binding(
                    get: { localValue },
                    set: { newValue in
                        // 🚀 Mise à jour optimiste locale IMMÉDIATE
                        localValue = newValue
                        isUpdating = true
                        
                        // Appel API en arrière-plan
                        onToggle(newValue)
                        
                        // Reset du flag d'update
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isUpdating = false
                        }
                    }
                ))
                .labelsHidden()
            }
            
            if localValue {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.caption2)
            }
        }
        .opacity(isUpdating ? 0.7 : 1.0)
    }
} 