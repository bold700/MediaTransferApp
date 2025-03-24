import SwiftUI
import UIKit

@main
struct MediaTransferApp: App {
    init() {
        // Zorg ervoor dat de app altijd in fullscreen mode start
        if UIDevice.current.userInterfaceIdiom == .pad {
            UIApplication.shared.delegate?.window??.overrideUserInterfaceStyle = .light
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
} 