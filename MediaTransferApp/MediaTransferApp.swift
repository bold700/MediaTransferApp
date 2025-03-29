import SwiftUI
import UIKit

@main
struct MediaTransferApp: App {
    init() {
        // Ensure the app always starts in fullscreen mode
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