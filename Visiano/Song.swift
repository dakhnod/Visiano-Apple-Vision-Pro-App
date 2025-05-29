struct Song: Codable, Hashable {
    struct Note: Codable, Hashable {
        let index: UInt8;
        let sharp: Bool;
        let start: Float;
        let end: Float;
        let duration: Float;
    }
    let duration: Float
    let notes: [[Note]]
}


