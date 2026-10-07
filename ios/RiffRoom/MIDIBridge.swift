import Foundation
import CoreMIDI

/// Connects every MIDI source iOS knows about (USB, Bluetooth paired in-app, network) and forwards
/// channel messages (notes, pedals) to the page through `window.__riffMidi`.
final class MIDIBridge {
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var started = false
    private var connected: [Int: MIDIEndpointRef] = [:]     // page id -> source
    private var runningStatus: [Int: UInt8] = [:]           // touched only on the MIDI thread
    private let send: (String) -> Void

    init(send: @escaping (String) -> Void) { self.send = send }

    func start() {
        if !started {
            started = true
            MIDIClientCreateWithBlock("Riff Room" as CFString, &client) { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }          // a device came or went
            }
            MIDIInputPortCreateWithBlock(client, "Riff Room input" as CFString, &port) { [weak self] packets, refCon in
                self?.receive(packets, sourceId: Int(bitPattern: refCon))
            }
        }
        refresh()
    }

    /// Reconnects all sources and tells the page which devices exist.
    func refresh() {
        guard started else { return }
        for (_, source) in connected { MIDIPortDisconnectSource(port, source) }
        connected.removeAll()
        var devices: [[String: String]] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            let id = index + 1                                        // never 0, so the refCon pointer is never nil
            connected[id] = source
            MIDIPortConnectSource(port, source, UnsafeMutableRawPointer(bitPattern: id))
            devices.append(["id": String(id), "name": Self.displayName(of: source)])
        }
        if let data = try? JSONSerialization.data(withJSONObject: devices),
           let json = String(data: data, encoding: .utf8) {
            send("window.__riffMidi && window.__riffMidi.devices(\(json))")
        }
    }

    private static func displayName(of endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr, let value = name?.takeRetainedValue() {
            return value as String
        }
        return "MIDI device"
    }

    /// Splits packets into single messages (handles running status, skips SysEx and clock).
    private func receive(_ list: UnsafePointer<MIDIPacketList>, sourceId: Int) {
        var messages: [[UInt8]] = []
        for packet in list.unsafeSequence() {
            let length = min(Int(packet.pointee.length), 256)
            let bytes: [UInt8] = withUnsafeBytes(of: packet.pointee.data) { Array($0.prefix(length)) }
            var i = 0
            while i < bytes.count {
                var status = bytes[i]
                if status >= 0xF8 { i += 1; continue }                       // real-time: clock, active sensing
                if status == 0xF0 {                                           // SysEx: skip to F7
                    while i < bytes.count && bytes[i] != 0xF7 { i += 1 }
                    i += 1; continue
                }
                if status >= 0xF0 {                                           // other system messages
                    i += 1 + (status == 0xF2 ? 2 : (status == 0xF1 || status == 0xF3) ? 1 : 0)
                    continue
                }
                if status >= 0x80 { runningStatus[sourceId] = status; i += 1 }
                else if let running = runningStatus[sourceId] { status = running }
                else { i += 1; continue }
                let dataCount = (status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0) ? 1 : 2
                guard i + dataCount <= bytes.count else { break }
                messages.append([status] + Array(bytes[i..<(i + dataCount)]))
                i += dataCount
            }
        }
        guard !messages.isEmpty else { return }
        let js = messages
            .map { "window.__riffMidi.message('\(sourceId)',[\($0.map { String($0) }.joined(separator: ","))])" }
            .joined(separator: ";")
        DispatchQueue.main.async { [weak self] in self?.send(js) }
    }

    /// Injected before the page loads: a small Web MIDI implementation the page uses like Chrome's.
    static let shimJS = """
    (function () {
      if (window.__riffMidi) return;
      window.RIFF_NATIVE = true;
      var post = function (m) { try { window.webkit.messageHandlers.riff.postMessage(m); } catch (e) {} };
      var inputs = new Map(), outputs = new Map(), access = null, waiters = [];
      function Input(id, name) {
        this.id = id; this.name = name; this.manufacturer = ""; this.type = "input";
        this.state = "connected"; this.connection = "open"; this.onmidimessage = null; this._l = [];
      }
      Input.prototype.addEventListener = function (t, f) { if (t === "midimessage") this._l.push(f); };
      Input.prototype.removeEventListener = function (t, f) { this._l = this._l.filter(function (x) { return x !== f; }); };
      Input.prototype.open = function () { return Promise.resolve(this); };
      Input.prototype.close = function () { return Promise.resolve(this); };
      Input.prototype._emit = function (bytes) {
        var ev = { data: new Uint8Array(bytes), timeStamp: performance.now(), target: this };
        if (this.onmidimessage) this.onmidimessage(ev);
        this._l.forEach(function (f) { f(ev); });
      };
      window.__riffMidi = {
        devices: function (list) {
          var seen = {};
          list.forEach(function (d) { seen[d.id] = 1; var cur = inputs.get(d.id); if (!cur || cur.name !== d.name) inputs.set(d.id, new Input(d.id, d.name)); });
          Array.from(inputs.keys()).forEach(function (k) { if (!seen[k]) inputs.delete(k); });
          waiters.splice(0).forEach(function (f) { f(); });
          if (access && typeof access.onstatechange === "function") access.onstatechange({ port: null });
        },
        message: function (id, bytes) { var i = inputs.get(id); if (i) i._emit(bytes); }
      };
      navigator.requestMIDIAccess = function () {
        return new Promise(function (resolve) {
          waiters.push(function () {
            if (!access) access = { inputs: inputs, outputs: outputs, sysexEnabled: false, onstatechange: null };
            resolve(access);
          });
          post({ type: "midiStart" });
        });
      };
      window.riffNative = { pairBluetooth: function () { post({ type: "bluetooth" }); } };
    })();
    """
}
