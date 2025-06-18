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
        
        // 7 keys in an octave, after all
        let octaveIndex = note.octave * 7
        
        // index inside an octave
        let noteIndex = switch note.name {
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
                
        // +2 to compensate for two stray white keys on the left
        return Song.Note(index: UInt8(octaveIndex + noteIndex + 2), sharp: note.isSharp, start: start, end: end, duration: duration)
    }
    
    func handleURL(url: URL) {
        
        // Request access to security-scoped resource
        var needsSecurityScopedAccess = false
        var didStartAccessing = false

        // Check if the file is outside the app sandbox (like from Files app)
        // Bundle resources are typically in the app's directory
        if !url.path.hasPrefix(Bundle.main.bundlePath) {
            needsSecurityScopedAccess = true
        }

        if needsSecurityScopedAccess {
            didStartAccessing = url.startAccessingSecurityScopedResource()
            if !didStartAccessing {
                print("Failed to access security-scoped resource")
                return
            }
        }

        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            // get the file name
            selectedFileName = url.lastPathComponent
            
            tracks = []
            
            selectedMidiFile = try MIDIFile(midiFile: url)
            
            if let selectedMidiFile {
                var preselectedCount = 0
                
                for trackIndex in 1..<selectedMidiFile.tracks.count {
                    let track = selectedMidiFile.tracks[trackIndex]
                    
                    // try to get the name of this track
                    // for example "Left hand"
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

                    // Try to enable all tracks that appear to be designated for a hand
                    let preSelected = name.lowercased().contains("hand")
                    if preSelected {
                        preselectedCount += 1
                    }
                    tracks.append(TrackCandidate(
                        index: tracks.count,
                        name: name,
                        selected: preSelected,
                        track: track
                    ))
                }
                
                // Fallback for when no tracks could be identified to be playable by hand
                if preselectedCount == 0 {
                    if let firstTrackIndex = tracks.indices.first {
                        tracks[firstTrackIndex].selected = true
                    }
                }
            }
        } catch {
            print("Failed to load MIDI file:", error)
        }
    }

     var body: some View {
         VStack(spacing: 20) {
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
              
             // This gets updated automatically when "tracks" is modified
             // which happens then the user selects a new MIDI file
             if !tracks.isEmpty {
                 VStack {
                     Text("Tracks in \(selectedFileName):")
                         .font(.headline)
                     
                     // Here, we allow the user to select
                     // which tracks he wants to be included in the player
                     VStack {
                         ForEach($tracks, id: \.index) { $trackCandidate in
                             Toggle(trackCandidate.name, isOn: $trackCandidate.selected)
                         }
                     }
                     // again, this gets shown automatically once "errorShown" changes
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
                             // the default speed, if none given
                             var bpm = 120.0
                             
                             // try to extract the "beats per minute" from the first track
                             // as it seems to be normal to designate the first track to this
                             for fileEvent in selectedMidiFile.tracks[0].events {
                                 if case .tempo(_, let event) = fileEvent {
                                     bpm = event.bpmEncoded
                                     break
                                 }
                             }
                             
                             // The following few lines should calculate the accurate speed
                             // for each track.
                             // Currently, there is no better way to accomplish this:
                             // https://github.com/orchetect/MIDIKit/discussions/243
                             let secondsPerTick: Float = {switch(selectedMidiFile.timeBase) {
                             case .musical(let ticksPerQuarterNote):
                                 return Float(60.0 / bpm / Double(ticksPerQuarterNote))
                             case .timecode(let smpteFormat, let ticksPerFrame):
                                 // unhandled, will hopefully not occur
                                 return 1000
                             }}()
                             
                             for selectedCandidate in tracks where selectedCandidate.selected {
                                 // since MIDI defines "pressed" and "released" as seperate events,
                                 // and the sequence might very well be "pressed A" -> "pressed B" -> "released A"
                                 // we need to keep track which notes were opened at which time
                                 var openNotes = [String: Float]()
                                 var currentTick = UInt32(0)
                                 
                                 // final assembly of notes
                                 var notesList = [Song.Note]()
                                 
                                 for fileEvent in selectedCandidate.track.events {
                                     let event = fileEvent.event()
                                     
                                     // we do not have absolute timestamps, but only relative tick count
                                     // to the previous event.
                                     // Hence, we track the absolute progress here.
                                     currentTick += fileEvent.delta.ticksValue(using: .musical(ticksPerQuarterNote: 1000))
                                     
                                     // convert ticks to seconds
                                     let noteEnd = Float(currentTick) * secondsPerTick
                                     
                                     // bit wasteful to run this for every note, but mehr
                                     // happens only once anyway
                                     songDuration = max(songDuration, noteEnd)
                                     
                                     switch(event) {
                                     case let .noteOn(event):
                                         // sometimes, a key release is encoded as a press with zero velocity instead of a keyOff
                                         if event.velocity.unitIntervalValue == 0.0 {
                                             if let start = openNotes[event.note.stringValue()] {
                                                 notesList.append(
                                                    convertEventToNode(note: event.note, start: start, end: noteEnd)
                                                 )
                                             }
                                             break;
                                         }
                                         
                                         // register the timestamp of this key being pressed
                                         openNotes[event.note.stringValue()] = Float(currentTick) * secondsPerTick;
                                     case let .noteOff(event):
                                         // calculate the length of this keypress
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
                 .padding(15)
                 .background(Color.gray.opacity(0.45))
                 .cornerRadius(40)
                 .frame(width: 300)
             }
         }
    }
}


