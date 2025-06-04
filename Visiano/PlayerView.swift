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

    @State private var showPicker = false
    @State private var displayLink: CADisplayLink?
    @State private var speed = 1.0
    @State private var progress: Float
    // angle of attack of notes falling onto the piano
    @State private var angle = 45.0
    
    @State private var playing = false

    // is the progress bar currently being dragged?
    @State private var dragged = false
    
    // The size of our scene as god intended, before the user changed it
    @State private var originalSize: Size3D?
    @State private var sceneScale: Float = 1.0
    
    // save all entites related to displaying/animating/tapping keys
    @State var noteIndicators = [ModelEntity]()
    @State var collisionEntities = [Entity]()
    @State var sharpIndicators = [Int: ModelEntity]()
    
    // store all note audio files
    @State var regularNoteFiles = [AudioFileResource]()
    @State var sharpNoteFiles = [Int: AudioFileResource]()
    
    // The timestamp at which playback was started
    @State var playStart = 0.0
    // The timestamp at which playback was paused
    @State var pausedTime = 0.0
    
    @State private var noteSounds = true
    	
    let WHITE_KEY_WIDTH = 0.0235 as Float
    let WHITE_KEY_LENGTH = 0.15 as Float
    let BLACK_KEY_WIDTH = 0.01 as Float
    let NOTEVIEW_Z_OFFSET = 0.025 as Float
    var KEYBOARD_START = 0 as Float
    let WHITE_KEY_COUNT = 52
    // 5 seconds before the first note lands
    let SONG_HEADROOM = 5 as Float
    
    let BLACK_KEY_START: Float
    let OCTAVE_WIDTH: Float
    let KEYBOARD_WIDTH: Float // 1,222
    let SONG_LENGTH_METERS: Float
    
    let METERS_PER_SECOND: Float = 0.05
    
    // stores the minimum progress like -0.05 for 5%
    // is needed, since there is 5 seconds of headroom before the first note
    // and this stores the headroom in unit 1
    var PROGRESS_MIN: Float
    
    // all notes and meta information about the played piece
    var song: Song
    
    let HAND_COLORS: [UIColor] = [.blue, .red, .green, .cyan, .yellow]
    
    // stores an index to the lastly played notes
    // so that calculating the currently played notes doesn't 
    // have to take into consideration already played notes
    @State var trackPointers = [Int]()
    
    // root entity holding all views
    let anchor = Entity()
    // planar view holding all note bars
    var noteView = Entity()
    
    init(song: Song) {
        self.song = song
        
        // keyboard is lead by three white keys
        BLACK_KEY_START = 3 * WHITE_KEY_WIDTH
        OCTAVE_WIDTH = 7 * WHITE_KEY_WIDTH
        KEYBOARD_WIDTH = Float(WHITE_KEY_COUNT) * WHITE_KEY_WIDTH // 1,222
        // offset by half a keyboard
        KEYBOARD_START = KEYBOARD_WIDTH / -2
        // final length of the notes entity
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
    
    // converts a note into a bar entity
    func generateNote(note: Song.Note, index: Int) -> Entity {
        let handColor = HAND_COLORS[index % HAND_COLORS.count]
                
        // shorten by 5mm to allow for gaps between consecutive notes
        let length = (Float(note.duration) * METERS_PER_SECOND) - 0.002
        
        let width = note.sharp ? BLACK_KEY_WIDTH : WHITE_KEY_WIDTH
        
        let mesh = MeshResource.generateBox(size: SIMD3(width, length, 0))
        let material = SimpleMaterial(color: handColor, isMetallic: false)
        let bar = ModelEntity(mesh: mesh, materials: [material])
        
        // move bar up/down dependant on start (which is in seconds)
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
        let meshSize = SIMD3(BLACK_KEY_WIDTH, 0.00, 0.06)
        let mesh = MeshResource.generateBox(size: meshSize)
        let material = SimpleMaterial(color: .black, isMetallic: false)
        let key = ModelEntity(mesh: mesh, materials: [material])
        
        let xOffset = BLACK_KEY_START + (Float(index) * WHITE_KEY_WIDTH)
        key.transform.translation = [
            xOffset,
            0.001, // y offset to hover the black keys a bit above the white keys for improved tap detection
            -0.05
        ]
        
        // black keys can have a collision component bound to them, since they are always enabled
        key.components.set(InputTargetComponent(allowedInputTypes: .all))
        key.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: meshSize)], isStatic: true))
        
        container.addChild(key)
        
        sharpIndicators[index] = key

        let noteMapping = ["c", "d", "e", "f", "g", "a", "b"]
        let noteLetter = noteMapping[(index) % 7]
        let octave = (index + 7) / 7
        let noteResourceURL = Bundle.main.url(forResource: "\(octave)-\(noteLetter)s", withExtension: "wav", subdirectory: "notes")
        if let noteResourceURL {
            do {
                // store note audio data for later playback
                sharpNoteFiles[index] = (
                    try AudioFileResource.load(contentsOf: noteResourceURL)
                )
            } catch {
                print("error loading note", noteLetter, octave)
            }
        }else {
            print("missing note", noteLetter, octave)
        }
    }
    
    @MainActor func generateWhiteKey(container: Entity, index: Int) {
        let mesh = MeshResource.generateBox(size: SIMD3(0.004, 0.00, WHITE_KEY_LENGTH))
        let material = SimpleMaterial(color: .black, isMetallic: false)
        let divider = ModelEntity(mesh: mesh, materials: [material])
        divider.position.x = Float(index) * WHITE_KEY_WIDTH
        
        container.addChild(divider)
        
        // have to generate the indicators seperately since the indicators (that light up)
        // lie in between the dividers
        let indicatorSize = SIMD3(WHITE_KEY_WIDTH, 0.00, WHITE_KEY_LENGTH)
        let indicatorMesh = MeshResource.generateBox(size: indicatorSize)
        let indicatorMaterial = SimpleMaterial(color: .black, isMetallic: false)
        let indicator = ModelEntity(mesh: indicatorMesh, materials: [indicatorMaterial])
        
        indicator.position.x = (Float(index) * WHITE_KEY_WIDTH) + (WHITE_KEY_WIDTH / 2)
        indicator.isEnabled = false
        container.addChild(indicator)
        
        // creating the collisionEntity seperately since the indicator entities are mostly disabled
        // and thus don't receive and tap events
        let collisionEntity = Entity()
        collisionEntity.position.x = (Float(index) * WHITE_KEY_WIDTH) + (WHITE_KEY_WIDTH / 2)
        collisionEntity.components.set(InputTargetComponent(allowedInputTypes: .all))
        collisionEntity.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: indicatorSize)], isStatic: true))
        
        container.addChild(collisionEntity)
        collisionEntities.append(collisionEntity)
        
        noteIndicators.append(indicator)
        
        let noteMapping = ["c", "d", "e", "f", "g", "a", "b"]
        let noteLetter = noteMapping[(index + 5) % 7]
        let octave = (index + 5) / 7
        let noteResourceURL = Bundle.main.url(forResource: "\(octave)-\(noteLetter)", withExtension: "wav", subdirectory: "notes")
        if let noteResourceURL {
            do {
                regularNoteFiles.append(
                    try AudioFileResource.load(contentsOf: noteResourceURL)
                )
            } catch {
                print("error loading note", noteLetter, octave)
            }
        }else {
            print("missing note", noteLetter, octave)
        }
    }

    var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                // This will hold all entities for the keys
                let keyboard = Entity()
                
                anchor.addChild(noteView)
                anchor.addChild(keyboard)
                
                keyboard.transform.translation = [KEYBOARD_START, 0, 0.1]
                
                for index in 0..<WHITE_KEY_COUNT {
                    // filter out only real locations for black keys
                    if (index < 48) && [0, 1, 3, 4, 5].contains(index % 7) {
                        generateBlackKey(container: keyboard, index: index)
                    }
                    
                    generateWhiteKey(container: keyboard, index: index)
                }
                
                // Piece usually consists of (at least) left and right hand
                for (trackIndex, notes) in song.notes.enumerated() {
                    for note in notes {
                        noteView.addChild(generateNote(note: note, index: trackIndex))
                    }
                }
                
                content.add(anchor)
                
                // initialize trackPointers for each track
                for _ in song.notes {
                    trackPointers.append(0)
                }
                
                let controller = AnimationController { displayLink in
                    /*
                    Here, is gets a bit confusing.
                    Initially, I was using displayLink.targetTimestamp - displayLink.timestamp,
                    which gave me the delta time between two frames.
                    Unfortunately, in the sim this was not working, since that one is running with 60fps, unlinke the Vision (90 fps).
                    Also, we need to do a bit of trickery in order to make dragging and speed changes properly work.
                    In any case, I am sorry for whoever has to maintain this. Sorry to future me if applicable.
                    */

                    // we have to adjust the start of playback when dragging to move everything in time            
                    if dragged {
                        playStart = displayLink.targetTimestamp - (Double(song.duration) * Double(progress)) - Double(SONG_HEADROOM)
                        return
                    }
                    if !playing {
                        // we do this only once when transitioning between playing and paused state
                        // since this is the only place where we have access to displayLink.targetTimestamp
                        if playStart != 0.0 {
                            pausedTime = displayLink.targetTimestamp - playStart
                            playStart = 0.0
                        }
                        return
                    }
                    
                    // again, we are asynchronously handling the transision between paused and playing state
                    if playStart == 0.0 {
                        playStart = displayLink.targetTimestamp
                        if pausedTime != 0.0 {
                            playStart -= pausedTime
                        }
                        return
                    }
                    
                    let playedTime = Float(displayLink.targetTimestamp - playStart - Double(SONG_HEADROOM))  * Float(speed)
                    
                    progress = (playedTime / song.duration)
                    
                    /*
                    Here, we are trying to figure out which notes should currently be pressed.
                    The easiest approach would be to just iterate over all nodes and check which ones
                    lie above the current timestamp (in the time dimension).
                    This would iterate over thousands of notes per frame in the worst case.

                    hence, we just remember which notes have already passed using the trackPointers.
                    Starting from the closest unplayed note, we look up the track until we find a note 
                    that has not yet started.
                    In that case, we go to the next track.

                    This way, our pool of potential notes shrinks with every played note.
                    */

                    // iterate over all tracks (left hand, right hand...)
                    for (trackIndex, track) in song.notes.enumerated() {
                        // iterate from the last fully played note up to the end of the track
                        for i in trackPointers[trackIndex]..<track.count {
                            let note = track[i]
                            let noteIndex = Int(note.index + 2)
                            
                            if playedTime < note.start {
                                // have not reached the note yet
                                break;
                            }
                            
                            
                            if playedTime > (note.end - 0.05) {
                                // note has passed
                                // we can exclude it on the next iteration
                                trackPointers[trackIndex] += 1

                                // turn off the indicator for this note
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
                            
                            // at this point we are inside the note (in the time dimension, start <= now <= end)
                            // and we turn on the indicator
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
                    
                    // reset to start if song has passed
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
                
                // create a displayLink to register a callback for each frame
                displayLink = CADisplayLink(target: controller, selector: #selector(controller.animationCallback))
                
                displayLink?.add(to: .main, forMode: .default)
            } update: { content in
                // This block gets called before a frame if a state variable changes,
                // which is the case in every frame thanks to the displayLink

                // revert the shift of anchor
                // without this, parts of the UI would start clipping out
                // since the scene is first scaled, then translated
                anchor.transform.translation = [
                    0.0,
                    -0.30 * sceneScale,
                    0.1 * sceneScale
                ]

                // apply global scale
                if let scene = content.entities.first {
                    scene.transform.scale = [sceneScale, sceneScale, sceneScale]
                }
                
                // radians
                let angleRad = Float(angle / -180.0 * Double.pi)
                
                // the total amount by which the noteView has to be shifted
                let hypotenuse = Float(-SONG_LENGTH_METERS * Float(progress))
                
                noteView.transform.rotation = simd_quatf(angle: angleRad, axis: [1.0, 0.0, 0.0])
                
                // Why do we need trigonometry here?
                // The way that the transform works we cannot shift the noteView
                // and also have a dynamic angle, since the view gets rotated first,
                // then translated.
                // This leads to the rotated view just going down into the ground.
                noteView.transform.translation = [
                    KEYBOARD_START + WHITE_KEY_WIDTH / 2,
                    hypotenuse * cos(angleRad),
                    hypotenuse * sin(angleRad) + NOTEVIEW_Z_OFFSET
                ]
                
            }
            .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { event in
                if !noteSounds {
                    return
                }
                
                func getPlayedNoteIndex () -> (Int?, Bool) {
                    // Here we are trying to figure out which note (Entity) was pressed
                    // First white keys (more likely) and then black.
                    for (index, indicator) in sharpIndicators {
                        if indicator != event.entity {
                            continue
                        }
                        return (index, true)
                    }
                    
                    for (index, indicator) in collisionEntities.enumerated() {
                        if indicator != event.entity {
                            continue
                        }
                        return (index, false)
                    }
                    
                    return (nil, false)
                }
                
                let (playedIndex, sharp) = getPlayedNoteIndex()
                
                if noteSounds {
                    if let playedIndex {
                        if sharp {
                            if let file = sharpNoteFiles[playedIndex] {
                                event.entity.playAudio(file)
                            }
                        }else {
                            event.entity.playAudio(regularNoteFiles[playedIndex])
                        }
                    }
                }
            })
            .onAppear {
                // backup the original size of the window
                // to calculate a factor when resizing
                originalSize = geometry.size
            }
            .onDisappear() {
                // without invalidating the DL our callback gets called even after closing the window
                displayLink?.invalidate()
            }
            .onChange(of: geometry.size) { newSize in
                // as promised, recalculate the scene scale based on the new window size
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
                            // this gets called when the slider is pinched/released
                            dragged = editing
                            
                            if !editing {
                                // reset all track pointers
                                // since we find ourselves in a different part of the track
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
                    
                    Toggle(isOn: $noteSounds) {
                        Text("Sounds")
                    }
                    .padding(15)
                    .background(Color.gray.opacity(0.45))
                    .cornerRadius(40)
                }
            }
            .ornament(attachmentAnchor: .scene(.bottomFront)) {
                if !playing {
                    // move Play button out of the way
                    // when playback is active
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
