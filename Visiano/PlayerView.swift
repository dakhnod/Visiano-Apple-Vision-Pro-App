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
    @State private var displayLink: CADisplayLink?
    @State private var speed = 1.0
    @State private var progress: Float
    @State private var angle = 45.0
    
    @State private var playing = false
    @State private var dragged = false
    
    @State private var originalSize: Size3D?
    @State private var sceneScale: Float = 1.0
    
    @State var noteIndicators = [ModelEntity]()
    @State var sharpIndicators = [Int: ModelEntity]()
    
    @State var playStart = 0.0
    @State var pausedTime = 0.0
    	
    let WHITE_KEY_WIDTH = 0.0235 as Float
    let WHITE_KEY_LENGTH = 0.15 as Float
    let BLACK_KEY_WIDTH = 0.01 as Float
    let NOTEVIEW_Z_OFFSET = 0.025 as Float
    var KEYBOARD_START = 0 as Float
    let WHITE_KEY_COUNT = 52
    let SONG_HEADROOM = 5 as Float
    
    let BLACK_KEY_START: Float
    let OCTAVE_WIDTH: Float
    let KEYBOARD_WIDTH: Float // 1,222
    let SONG_LENGTH_METERS: Float
    
    let METERS_PER_SECOND: Float = 0.05
    
    var PROGRESS_MIN: Float
    
    var song: Song
    
    let HAND_COLORS: [UIColor] = [.blue, .red, .green, .cyan, .yellow]
    
    @State var trackPointers = [Int]()
    
    let anchor = Entity()
    var noteView = Entity()
    
    init(song: Song) {
        self.song = song
        
        BLACK_KEY_START = 3 * WHITE_KEY_WIDTH
        OCTAVE_WIDTH = 7 * WHITE_KEY_WIDTH
        KEYBOARD_WIDTH = Float(WHITE_KEY_COUNT) * WHITE_KEY_WIDTH // 1,222
        KEYBOARD_START = KEYBOARD_WIDTH / -2
        SONG_LENGTH_METERS = song.duration * METERS_PER_SECOND
        
        // always give 5 seconds of headroom
        PROGRESS_MIN = -SONG_HEADROOM / song.duration
        progress = PROGRESS_MIN
    }
    
    class AnimationController {
        var callback: (_ displayLink: CADisplayLink) -> Void
        
        init(callback: @escaping (_ displayLink: CADisplayLink) -> Void) {
            self.callback = callback
        }
        
        @objc func animationCallback(displayLink: CADisplayLink) {
            callback(displayLink)
        }
    }
    
    func generateNote(note: Song.Note, index: Int) -> Entity {
        let handColor = HAND_COLORS[index % HAND_COLORS.count]
                
        // shorten by 5mm to allow for gaps
        let length = (Float(note.duration) * METERS_PER_SECOND) - 0.002
        
        let width = note.sharp ? BLACK_KEY_WIDTH : WHITE_KEY_WIDTH
        
        let mesh = MeshResource.generateBox(size: SIMD3(width, length, 0))
        let material = SimpleMaterial(color: handColor, isMetallic: false)
        let bar = ModelEntity(mesh: mesh, materials: [material])
        
        bar.transform.translation = [
            (Float(note.index) * WHITE_KEY_WIDTH) + (2 * WHITE_KEY_WIDTH),
            (Float(note.start) * METERS_PER_SECOND) + (length / 2),
            0
        ]
        
        if note.sharp {
            bar.transform.translation.x += WHITE_KEY_WIDTH / 2
        }
        
        return bar
    }		
    
    @MainActor func generateBlackKey(container: Entity, index: Int) {
        let mesh = MeshResource.generateBox(size: SIMD3(BLACK_KEY_WIDTH, 0.00, 0.06))
        let material = SimpleMaterial(color: .black, isMetallic: false)
        let key = ModelEntity(mesh: mesh, materials: [material])
        
        let xOffset = BLACK_KEY_START + (Float(index) * WHITE_KEY_WIDTH)
        key.transform.translation = [
            xOffset,
            0,
            -0.05
        ]
        
        container.addChild(key)
        
        sharpIndicators[index] = key
    }
    
    @MainActor func generateWhiteKey(container: Entity, index: Int) {
        let mesh = MeshResource.generateBox(size: SIMD3(0.004, 0.00, WHITE_KEY_LENGTH))
        let material = SimpleMaterial(color: .black, isMetallic: false)
        let divider = ModelEntity(mesh: mesh, materials: [material])
        divider.position.x = Float(index) * WHITE_KEY_WIDTH
        
        container.addChild(divider)
        
        let indicatorMesh = MeshResource.generateBox(size: SIMD3(WHITE_KEY_WIDTH, 0.00, WHITE_KEY_LENGTH))
        let indicatorMaterial = SimpleMaterial(color: .black, isMetallic: false)
        let indicator = ModelEntity(mesh: indicatorMesh, materials: [indicatorMaterial])
        
        indicator.position.x = (Float(index) * WHITE_KEY_WIDTH) + (WHITE_KEY_WIDTH / 2)
        indicator.isEnabled = false
        container.addChild(indicator)
        
        noteIndicators.append(indicator)
    }

    var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                // Add the initial RealityKit content
                
                let keyboard = Entity()
                
                anchor.addChild(noteView)
                anchor.addChild(keyboard)
                
                keyboard.transform.translation = [KEYBOARD_START, 0, 0.1]
                
                for index in 0..<WHITE_KEY_COUNT {
                    generateWhiteKey(container: keyboard, index: index)
                    
                    if (index < 48) && [0, 1, 3, 4, 5].contains(index % 7) {
                        generateBlackKey(container: keyboard, index: index)
                    }
                }
                
                for (index, notes) in song.notes.enumerated() {
                    for note in notes {
                        noteView.addChild(generateNote(note: note, index: index))
                    }
                }
                
                content.add(anchor)
                
                for _ in song.notes {
                    trackPointers.append(0)
                }
                
                let controller = AnimationController { displayLink in
                    if dragged {
                        playStart = displayLink.targetTimestamp - (Double(song.duration) * Double(progress)) - Double(SONG_HEADROOM)
                        return
                    }
                    guard playing else {
                        if playStart != 0.0 {
                            pausedTime = displayLink.targetTimestamp - playStart
                            playStart = 0.0
                        }
                        return
                    }
                    
                    if playStart == 0.0 {
                        playStart = displayLink.targetTimestamp
                        if pausedTime != 0.0 {
                            playStart -= pausedTime
                        }
                        return
                    }
                    
                    let playedTime = Float(displayLink.targetTimestamp - playStart - Double(SONG_HEADROOM))
                    
                    progress = playedTime / song.duration
                    
                    for (trackIndex, track) in song.notes.enumerated() {
                        for i in trackPointers[trackIndex]..<track.count {
                            let note = track[i]
                            let noteIndex = Int(note.index + 2)
                            
                            if playedTime < note.start {
                                // have not reached the note yet
                                break;
                            }
                            
                            
                            if playedTime > (note.end - 0.05) {
                                // note has passed
                                trackPointers[trackIndex] += 1
                                if note.sharp {
                                    if let indicator = sharpIndicators[noteIndex - 2] {
                                        if var model = indicator.model {
                                            model.materials = [SimpleMaterial(color: .black, isMetallic: false)]
                                            indicator.model = model
                                        }
                                    }
                                     
                                }else{
                                    noteIndicators[noteIndex].isEnabled = false
                                }
                                continue
                            }
                            let color = HAND_COLORS[trackIndex % HAND_COLORS.count]
                            
                            // at this point we are inside the note
                            if note.sharp {
                                if let indicator = sharpIndicators[noteIndex - 2]{
                                    if var model = indicator.model {
                                        model.materials = [SimpleMaterial(color: color, isMetallic: false)]
                                        indicator.model = model
                                    }
                                }
                            }else{
                                if var model = noteIndicators[noteIndex].model {
                                    model.materials = [SimpleMaterial(color: color, isMetallic: false)]
                                    noteIndicators[noteIndex].model = model
                                }
                                noteIndicators[noteIndex].isEnabled = true
                            }
                        }
                    }
                    
                    if progress > 1.0 {
                        playing = false
                        progress = PROGRESS_MIN
                        pausedTime = 0
                        playStart = 0
                        
                        for i in 0..<trackPointers.count {
                            trackPointers[i] = 0
                        }
                    }
                }
                
                displayLink = CADisplayLink(target: controller, selector: #selector(controller.animationCallback))
                
                displayLink?.add(to: .main, forMode: .default)
            } update: { content in
                anchor.transform.translation = [
                    0.0,
                    -0.30 * sceneScale,
                    0.1 * sceneScale
                ]
                // Update the RealityKit content when SwiftUI state changes
                if let scene = content.entities.first {
                    scene.transform.scale = [sceneScale, sceneScale, sceneScale]
                }
                
                let angleRad = Float(angle / -180.0 * Double.pi)
                
                let hyp = Float(-SONG_LENGTH_METERS * Float(progress))
                
                noteView.transform.rotation = simd_quatf(angle: angleRad, axis: [1.0, 0.0, 0.0])
                
                noteView.transform.translation = [
                    KEYBOARD_START + WHITE_KEY_WIDTH / 2,
                    hyp * cos(angleRad),
                    hyp * sin(angleRad) + NOTEVIEW_Z_OFFSET
                ]
                
            }
            .gesture(TapGesture().targetedToAnyEntity().onEnded { _ in
                enlarge.toggle()
            })
            .toolbar {
                ToolbarItemGroup(placement: .bottomOrnament) {
                }
            }
            .onAppear {
                originalSize = geometry.size
            }
            .onChange(of: geometry.size) { newSize in
                if let originalSize {
                    sceneScale = Float(newSize.height / originalSize.height)
                }
            }
            
            .ornament(
                attachmentAnchor: .scene(.topFront),
                contentAlignment: .center
            ) {
                HStack (spacing: 12) {
                    HStack {
                        Text("Speed")
                            .font(.headline)
                        
                        Slider(value: $speed, in: 0...3, step: 0.01)
                    }
                    .padding(15)
                    .background(Color.gray.opacity(0.45))
                    .cornerRadius(40)
                    
                    HStack {
                        Text("Angle")
                            .font(.headline)
                        
                        Slider(value: $angle, in: 1...90)
                    }
                    .padding(15)
                    .background(Color.gray.opacity(0.45))
                    .cornerRadius(40)
                    
                    if playing {
                        Button("Pause") {
                            playing = false
                        }
                    }
                    
                    HStack {
                        Text("Progress")
                            .font(.headline)
                            .fixedSize(horizontal: true, vertical: true)
                        
                        Slider(value: $progress, in: PROGRESS_MIN...1, step: 0.01) { editing in
                            dragged = editing
                            
                            if !editing {
                                for i in 0..<trackPointers.count {
                                    trackPointers[i] = 0
                                }
                            }
                        }
                            .frame(width: 600)
                    }
                    .padding(15)
                    .background(Color.gray.opacity(0.45))
                    .cornerRadius(40)
                }
            }
            .ornament(attachmentAnchor: .scene(.bottomFront)) {
                if !playing {
                    Button("Play") {
                        playing = true
                    }
                }
            }
            .supportedVolumeViewpoints([.front])
            // .frame(depth: 0.6)
            // .frame(width: 1.3, height: 0.6, alignment: .center)
        }
    }
}
