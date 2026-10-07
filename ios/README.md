# Riff Room iPad app

A small native app that opens https://pianoriffs.app and adds what Safari can't do on iPad:

- **MIDI from the piano** (USB through Apple's camera adapter, or Bluetooth), passed to the page as standard Web MIDI.
- **Bluetooth pairing built in**: Connect piano → *Pair Bluetooth piano* opens Apple's Bluetooth MIDI screen.
- **Mic mode** works too, and the screen stays on while practising.

The app shows the live site, so every Riff Room update arrives without rebuilding the app.

## Build it (Mac with Xcode)

1. Install Xcode from the Mac App Store, then XcodeGen: `brew install xcodegen`
2. In this folder: `xcodegen` (creates `RiffRoom.xcodeproj`), then `open RiffRoom.xcodeproj`
3. Xcode → Settings → Accounts: add your Apple ID.
4. Select the **RiffRoom** target → **Signing & Capabilities** → Team: your Apple ID.
   If Xcode says the bundle ID is taken, change `app.pianoriffs.riffroom` to something unique.
5. Plug in the iPad, unlock it, tap Trust. On the iPad turn on
   Settings → Privacy & Security → **Developer Mode** (it restarts).
6. Pick the iPad as the run destination and press ▶.
   First launch only: iPad Settings → General → VPN & Device Management → trust your developer profile.

## Free Apple ID vs Developer Program

- **Free Apple ID:** the app stops opening after 7 days. Press ▶ again with the iPad connected to renew it.
- **Apple Developer Program ($99/year):** installs last a year. Product → Archive → Distribute App → App Store Connect,
  then add the family as testers in **TestFlight**; they install it from the TestFlight app, no cable needed.
- **App Store:** the same archive can be submitted for review (usually 1–2 days). Apple rejects apps that are
  "just a website", so the review notes should mention the native MIDI bridge and Bluetooth MIDI pairing.

## How it works

- `RiffWebView.swift`: the web view, the Bluetooth pairing screen, microphone permission, links to other sites open in Safari.
- `MIDIBridge.swift`: CoreMIDI client that connects every MIDI source, splits packets into note messages and sends them
  to the page; also contains the small JavaScript (`shimJS`) that gives the page `navigator.requestMIDIAccess`.
- The page detects the app through `window.RIFF_NATIVE` and connects to the piano by itself.
