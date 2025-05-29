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
        
    var onProcess: ([[Note]]) -> Void
    
    func convertEventToNode(note: MIDINote, start: UInt32, currentTick: UInt32) -> Note{
        let duration = currentTick - start
        
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
        
        print(note.stringValue())
        
        return Note(index: UInt8(startIndex + octaveIndex), sharp: note.isSharp, start: start, end: start + duration, duration: duration)
    }

     var body: some View {
        Button("Pick MIDI File") {
            print("pressed")
            showPicker = true
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { urls in
                if let url = urls.first {
                    do {
                        selectedFileName = url.lastPathComponent
                        
                        tracks = []
                        
                        let midiFile = try MIDIFile(midiFile: url)
                        
                        for track in midiFile.tracks {
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
                    } catch {
                        print("Failed to load MIDI file:", error)
                    }
                }
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
            Button("Start playing") {
                var notesListList = [[Note]]()
                for selectedCandidate in tracks where selectedCandidate.selected {
                    var openNotes = [String: UInt32]()
                    var currentTick = UInt32(0)
                    
                    var notesList = [Note]()
                    
                    for fileEvent in selectedCandidate.track.events {
                        let event = fileEvent.event()
                        currentTick += fileEvent.delta.ticksValue(using: .musical(ticksPerQuarterNote: 100))
                        
                        switch(event) {
                        case let .noteOn(event):
                            if event.velocity.unitIntervalValue == 0.0 {
                                if let start = openNotes[event.note.stringValue()] {
                                    notesList.append(
                                        convertEventToNode(note: event.note, start: start, currentTick: currentTick)
                                    )
                                }
                                break;
                            }
                            
                            openNotes[event.note.stringValue()] = currentTick;
                        case let .noteOff(event):
                            if let start = openNotes[event.note.stringValue()] {
                                notesList.append(
                                    convertEventToNode(note: event.note, start: start, currentTick: currentTick)
                                )
                            }
                            break
                            
                        default:
                            break
                        }
                    }
                    
                    notesListList.append(notesList)
                }
                onProcess(notesListList)
            }
        }
    }
}


