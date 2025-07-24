struct GPTEtymologyResponse: Codable {
    let etymology: DirectEtymology
    
    // On n'a plus besoin de ces champs car on utilise directement la table language_locations
    // let languages: [LanguageAnalysis]
    // let sqlQueries: [String]
} 