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
        WindowGroup {
            MenuView() { notes in
                openWindow(value: notes)
            }
        }
        .windowStyle(.plain)
        
        WindowGroup(for: Song.self) { $song in
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

        /*
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
         */
    }
}
