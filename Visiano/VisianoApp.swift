//
//  VisianoApp.swift
//  Visiano
//
//  Created by SyDeveloper on 25.05.25.
//

import SwiftUI

@main
struct VisianoApp: App {
    @State private var appModel = AppModel()
    
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        /*
         You might ask yourself why we don't hide the window here, once the player is open.
         Turns out, it's not as easy.
         I tried:
         - Wrapping MenuView() in `if !playerOpen`
         - conditionally setting opacity
         - dismissing the WindowGroup
         
         Dismissing just didn't have any effect, while the other options somehow broke the animations
         inside of PlayerView.
         
         So for now, the window stays.
         */
        WindowGroup("Song selection") {
            MenuView() { notes in
                openWindow(value: notes)
            }
        }
        .windowStyle(.plain)
        
        // Whenever we call openWindow, passing a Song, this WindowGroup gets involved and opens a new PlayerView.
        // Through this mechanism there can only ever be one single Window for a particular song.
        WindowGroup("Piano player", for: Song.self) { $song in
            if let song {
                PlayerView(song: song)
                    .environment(appModel)
                    .volumeBaseplateVisibility(.visible)
                    // .frame(depth: 0.6)
                    // .frame(width: 1.3, height: 0.6)
            }
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 130, height: 60, depth: 60, in: .centimeters)
        .volumeWorldAlignment(.gravityAligned)
        .windowResizability(.contentSize)
    }
}
