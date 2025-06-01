import SwiftUI

import MIDIKitSMF
import MIDIKitCore

struct MenuView: View {
    struct TrackCandidate {
        let index: Int
        let name: String
        var selected: Bool
        let track: MIDIFile.Chunk.Track
    }
    
    @State private var showPicker = false
    @State private var tracks: [TrackCandidate] = []
    @State private var selectedFileName = ""
    @State private var selectedMidiFile: MIDIFile?
    @State private var errorMessage = ""
    @State private var errorShown = false
        
    var onProcess: (Song) -> Void
    
    func convertEventToNode(note: MIDINote, start: Float, end: Float) -> Song.Note {
        let duration = end - start
        
        let startIndex = note.octave * 7
        
        let octaveIndex = switch note.name {
        case .C: 0
        case .C_sharp: 0
        case .D: 1
        case .D_sharp: 1
        case .E: 2
        case .F: 3
        case .F_sharp: 3
        case .G: 4
        case .G_sharp: 4
        case .A: 5
        case .A_sharp: 5
        case .B: 6
        }
                
        return Song.Note(index: UInt8(startIndex + octaveIndex), sharp: note.isSharp, start: start, end: end, duration: duration)
    }
    
    func handleURL(url: URL) {
        do {
            selectedFileName = url.lastPathComponent
            
            tracks = []
            
            selectedMidiFile = try MIDIFile(midiFile: url)
            
            if let selectedMidiFile {
                for trackIndex in 1..<selectedMidiFile.tracks.count {
                    let track = selectedMidiFile.tracks[trackIndex]
                    
                    func getTrackName() -> String {
                        for fileEvent in track.events {
                            if let text = fileEvent.smfUnwrappedEvent.event as? MIDIKitSMF.MIDIFileEvent.Text {
                                if text.textType == .trackOrSequenceName {
                                    return text.text
                                }
                            }
                        }
                        
                        return "Unknown track"
                    }
                    
                    let name = getTrackName()
                    tracks.append(TrackCandidate(
                        index: tracks.count,
                        name: name,
                        selected: name.lowercased().contains("hand"),
                        track: track
                    ))
                }
            }
        } catch {
            print("Failed to load MIDI file:", error)
        }
    }

     var body: some View {
        Button("Pick MIDI File") {
            showPicker = true
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { urls in
                if let url = urls.first {
                    handleURL(url: url)
                }
            }
        }
         
         Text("Sample songs:")
        
        Button("Alle meine Entchen") {
            if let url = Bundle.main.url(forResource: "Alle_Meine_Entchen", withExtension: "mid", subdirectory: "MIDIs") {
                handleURL(url: url)
            }
        }
         
        if !tracks.isEmpty {
            Text("Tracks in \(selectedFileName):")
                .font(.headline)
            VStack {
                ForEach($tracks, id: \.index) { $trackCandidate in
                    Toggle(trackCandidate.name, isOn: $trackCandidate.selected)
                }
            }
            .alert(isPresented: $errorShown) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage)
                )
            }
            Button("Start playing") {
                let selectedTracksCount = tracks.count { track in track.selected }
                if selectedTracksCount == 0 {
                    errorMessage = "Please select at least one track"
                    errorShown = true
                    return
                }
                
                var notesListList = [[Song.Note]]()
                var songDuration = 0.0 as Float
                
                if let selectedMidiFile {
                    var bpm = 120.0
                    
                    for fileEvent in selectedMidiFile.tracks[0].events {
                        if case .tempo(_, let event) = fileEvent {
                            bpm = event.bpmEncoded
                            break
                        }
                    }
                    
                    let secondsPerTick: Float = {switch(selectedMidiFile.timeBase) {
                    case .musical(let ticksPerQuarterNote):
                        return Float(60.0 / bpm / Double(ticksPerQuarterNote))
                    case .timecode(let smpteFormat, let ticksPerFrame):
                        // unhandled
                        return 1000
                    }}()
                    
                    for selectedCandidate in tracks where selectedCandidate.selected {
                        var openNotes = [String: Float]()
                        var currentTick = UInt32(0)
                        
                        var notesList = [Song.Note]()
                        
                        for fileEvent in selectedCandidate.track.events {
                            let event = fileEvent.event()
                            currentTick += fileEvent.delta.ticksValue(using: .musical(ticksPerQuarterNote: 1000))
                            
                            let noteEnd = Float(currentTick) * secondsPerTick
                            
                            songDuration = max(songDuration, noteEnd)
                            
                            switch(event) {
                            case let .noteOn(event):
                                if event.velocity.unitIntervalValue == 0.0 {
                                    if let start = openNotes[event.note.stringValue()] {
                                        notesList.append(
                                            convertEventToNode(note: event.note, start: start, end: noteEnd)
                                        )
                                    }
                                    break;
                                }
                                
                                openNotes[event.note.stringValue()] = Float(currentTick) * secondsPerTick;
                            case let .noteOff(event):
                                if let start = openNotes[event.note.stringValue()] {
                                    notesList.append(
                                        convertEventToNode(note: event.note, start: start, end: noteEnd)
                                    )
                                }
                                break
                                
                            default:
                                break
                            }
                        }
                        
                        notesListList.append(notesList)
                    }
                    onProcess(Song(duration: songDuration, notes: notesListList))
                }
            }
        }
    }
}


