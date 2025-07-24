extension Array where Element: Hashable {
    func unique() -> [Element] {
        Array(Set(self))
    }
} 