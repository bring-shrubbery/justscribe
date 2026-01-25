//
//  justscribeApp.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import SwiftUI
import SwiftData

@main
struct justscribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            AppSettings.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup(id: "settings") {
            SettingsView()
                .frame(minWidth: 500, minHeight: 600)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
