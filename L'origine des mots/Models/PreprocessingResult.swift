import Foundation

public struct PreprocessingResult {
    let etymology: PreprocessedEtymology
    
    public init(etymology: PreprocessedEtymology) {
        self.etymology = etymology
    }
} 