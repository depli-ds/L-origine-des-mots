import Foundation

enum SourceState: String, Codable {
    case notFound
    case foundInCNRTL
    case foundInTLFi
    case foundInDatabase
    case foundWithCNRTLAndClaude
} 