import SwiftUI

/// Riff Room: a thin native shell around https://pianoriffs.app that adds what Safari can't do on iPad,
/// namely MIDI from the piano (USB or Bluetooth) and a built-in Bluetooth MIDI pairing screen.
@main
struct RiffRoomApp: App {
    var body: some Scene {
        WindowGroup {
            RiffWebView()
                .ignoresSafeArea()
                .background(Color(red: 0.07, green: 0.08, blue: 0.12))
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }   // keep the screen on while practising
        }
    }
}
