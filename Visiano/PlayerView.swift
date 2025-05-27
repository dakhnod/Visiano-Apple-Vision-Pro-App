//
//  ContentView.swift
//  Visiano
//
//  Created by SyDeveloper on 25.05.25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct PlayerView: View {

    @State private var enlarge = false
    @State private var showPicker = false
    @State var buttonVisible = true
    
    let WHITE_KEY_WIDTH = 0.0235 as Float
    let BLACK_KEY_WIDTH = 0.01 as Float
    
    var noteList: [Note]
    
    var noteView = Entity()
    
    func generateNote(note: Note) -> Entity {
        let lengthFactor = Float(10000)
        
        // shorten by 5mm to allow for gaps
        let length = (Float(note.duration) / lengthFactor) - 0.002
        
        let width = note.sharp ? BLACK_KEY_WIDTH : WHITE_KEY_WIDTH
        
        let mesh = MeshResource.generateBox(size: SIMD3(width, length, 0))
        let material = SimpleMaterial(color: .blue, isMetallic: false)
        let bar = ModelEntity(mesh: mesh, materials: [material])
        
        bar.transform.translation = [
            Float(note.index - 5) * WHITE_KEY_WIDTH,
            (Float(note.start) / lengthFactor) + (length / 2),
            0
        ]
        
        if note.sharp {
            bar.transform.translation.x += WHITE_KEY_WIDTH / 2
        }
        
        return bar
    }
    
    @MainActor func generateBlackKey(xOffset: Float) -> Entity{
        let mesh = MeshResource.generateBox(size: SIMD3(BLACK_KEY_WIDTH, 0.00, 0.06))
        let material = SimpleMaterial(color: .black, isMetallic: false)
        let key = ModelEntity(mesh: mesh, materials: [material])
        key.transform.translation = [
            xOffset,
            0,
            -0.05
        ]
        
        return key
    }
    
    @MainActor func generateWhiteKey(index: Int) -> Entity {
        let mesh = MeshResource.generateBox(size: SIMD3(0.004, 0.00, 0.15))
        let material = SimpleMaterial(color: .black, isMetallic: false)
        let divider = ModelEntity(mesh: mesh, materials: [material])
        divider.position.x = Float(index) * WHITE_KEY_WIDTH
        return divider
    }

    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            let anchor = Entity()
            
            let keyboard = Entity()
            
            let WHITE_KEY_COUNT = 52
            let BLACK_KEY_START = 3 * WHITE_KEY_WIDTH
            let OCTAVE_WIDTH = 7 * WHITE_KEY_WIDTH
            let KEYBOARD_WIDTH = Float(WHITE_KEY_COUNT) * WHITE_KEY_WIDTH // 1,222
            let KEYBOARD_START = KEYBOARD_WIDTH / -2
            
            noteView.transform.translation = [KEYBOARD_START + WHITE_KEY_WIDTH / 2, 0, 0.025]
            
            anchor.addChild(noteView)
            anchor.addChild(keyboard)
            
            
            keyboard.transform.translation = SIMD3(KEYBOARD_START, -0.25, 0.1)
            
            for index in 0..<WHITE_KEY_COUNT {
                keyboard.addChild(generateWhiteKey(index: index))
            }
            
            for offset in [0, 1, 3, 4, 5] {
                for index in 0..<7 {
                    keyboard.addChild(
                        generateBlackKey(xOffset: BLACK_KEY_START + (Float(index) * OCTAVE_WIDTH) + (Float(offset) * WHITE_KEY_WIDTH))
                    )
                }
            }
            
            for offset in [1] {
                keyboard.addChild(
                    generateBlackKey(xOffset: Float(offset) * WHITE_KEY_WIDTH)
                )
            }
            
            for note in noteList {
                noteView.addChild(generateNote(note: note))
            }
            
            content.add(anchor)
            
        } update: { content in
            // Update the RealityKit content when SwiftUI state changes
            /*
            if let scene = content.entities.first {
                let uniformScale: Float = enlarge ? 1.4 : 1.0
                scene.transform.scale = [uniformScale, uniformScale, uniformScale]
            }
             */
        }
        .gesture(TapGesture().targetedToAnyEntity().onEnded { _ in
            enlarge.toggle()
        })
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                if buttonVisible {
                    HStack (spacing: 12) {
                        Button("Play") {
                            Task {
                                noteView.move(
                                    to: Transform(
                                        translation: [0, -6, 0]
                                    ),
                                    relativeTo: noteView,
                                    duration: 100
                                )
                            }
                            buttonVisible = false
                        }
                    }
                }
            }
        }
        /*
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                VStack (spacing: 12) {
                    Button {
                        enlarge.toggle()
                    } label: {
                        Text(enlarge ? "Reduce RealityView Content" : "Enlarge RealityView Content")
                    }
                    .animation(.none, value: 0)
                    .fontWeight(.semibold)

                    ToggleImmersiveSpaceButton()
                }
            }
        }
         */
        
        /*
        .ornament(attachmentAnchor: .scene(.leading)) {
            VStack (spacing: 12) {
                Button("Pick MIDI File") {
                    showPicker = true
                }
                .sheet(isPresented: $showPicker) {
                    DocumentPicker { urls in
                        if let midiURL = urls.first {
                            // parseMIDIFile(url: midiURL)
                        }
                    }
                }
            }
        }
         */
         
    }
}
