//
//  RemarkableWordsView.swift
//  L'origine des mots
//
//  Created by Vadim Bernard on 21/11/2024.
//


import SwiftUI

struct RemarkableWordsView: View {
    let words: [RemarkableWord]
    let onWordTap: (RemarkableWord) -> Void
    
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            HStack {
                Text("Mots remarquables")
                    .font(.title2)
                Spacer()
                Button(action: {}) {
                    Label("Filtrer", systemImage: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            
            FlowLayout(spacing: 10) {
                ForEach(words) { word in
                    Button(action: { onWordTap(word) }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(word.word)
                                .font(.headline)
                            if let description = word.shortDescription {
                                Text(description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            HStack {
                                ForEach(word.tags.prefix(2), id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    RemarkableWordsView(
        words: [
            RemarkableWord(
                id: UUID(),
                word: "café",
                shortDescription: "De l'arabe قهوة (qahwa) via le turc kahve",
                tags: ["alimentation", "arabe", "turc"],
                createdAt: Date()
            ),
            RemarkableWord(
                id: UUID(),
                word: "algorithme",
                shortDescription: "Du nom du mathématicien perse Al-Khwârizmî",
                tags: ["sciences", "arabe", "mathématiques"],
                createdAt: Date()
            )
        ],
        onWordTap: { _ in }
    )
}