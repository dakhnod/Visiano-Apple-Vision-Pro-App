struct Song: Codable, Hashable {
    struct Note: Codable, Hashable {
        // actual index of this key on the keyboard. Leftmost is 0, ...
        let index: UInt8;

        // whether this is a black key
        let sharp: Bool;

        // start/end time, in seconds. First note has 0
        let start: Float;
        let end: Float;

        // seconds, again
        let duration: Float;
    }

    // duration of all notes combined
    let duration: Float

    // collections of notes for left hand, right, track, etc...
    let notes: [[Note]]
}


