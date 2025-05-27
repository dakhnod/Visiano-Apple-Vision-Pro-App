struct Note: Codable, Hashable {
    let index: UInt8;
    let sharp: Bool;
    let start: UInt32;
    let end: UInt32;
    let duration: UInt32;
}


