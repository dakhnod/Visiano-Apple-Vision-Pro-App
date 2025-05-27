import SwiftUI

import MIDIKitSMF
import MIDIKitCore

struct MenuView: View {
    @State private var showPicker = false
    
    var onProcess: ([Note]) -> Void
    
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
                        let midiFile = try MIDIFile(midiFile: url)
                        let tracks = midiFile.tracks
                        let leftHand = tracks[1]
                        
                        
                        var openNotes = [String: UInt32]()
                        var currentTick = UInt32(0)
                        
                        var notesList = [Note]()
                        
                        for fileEvent in leftHand.events {
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
                                    if let start = openNotes[event.note.stringValue()] {
                                        notesList.append(
                                            convertEventToNode(note: event.note, start: start, currentTick: currentTick)
                                        )
                                    }
                                }
                                break
                                
                            default:
                                break
                            }
                        }
                        
                        onProcess(notesList)
                    } catch {
                        print("Failed to load MIDI file:", error)
                    }
                }
            }
        }
    }
}
