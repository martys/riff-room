import SwiftUI
import WebKit
import CoreAudioKit

struct RiffWebView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> RiffViewController { RiffViewController() }
    func updateUIViewController(_ controller: RiffViewController, context: Context) {}
}

final class RiffViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let home = URL(string: "https://pianoriffs.app/")!
    static let ownHost = "pianoriffs.app"

    private var webView: WKWebView!
    private lazy var midi = MIDIBridge { [weak self] js in
        self?.webView.evaluateJavaScript(js, completionHandler: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let background = UIColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1)
        view.backgroundColor = background

        let contentController = WKUserContentController()
        // Gives the page navigator.requestMIDIAccess, backed by CoreMIDI in MIDIBridge.
        contentController.addUserScript(WKUserScript(source: MIDIBridge.shimJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        contentController.add(WeakMessageHandler(self), name: "riff")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        view.addSubview(webView)
        webView.load(URLRequest(url: Self.home))
    }

    // MARK: Messages from the page

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "midiStart": midi.start()
        case "bluetooth": showBluetoothPairing()
        default: break
        }
    }

    /// Apple's standard Bluetooth MIDI screen: lists nearby Bluetooth MIDI devices (the Kawai shows up here).
    private func showBluetoothPairing() {
        let pairing = CABTMIDICentralViewController()
        pairing.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeBluetoothPairing))
        let nav = UINavigationController(rootViewController: pairing)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    @objc private func closeBluetoothPairing() {
        dismiss(animated: true) { [weak self] in self?.midi.refresh() }
    }

    // MARK: Microphone (mic mode) without a second prompt from the web view

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host.hasSuffix(Self.ownHost) ? .grant : .prompt)
    }

    // MARK: Links to other sites open in Safari

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let host = url.host,
           navigationAction.navigationType == .linkActivated, !host.hasSuffix(Self.ownHost) {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(url) }
        return nil
    }

    // MARK: No internet

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Only real connection problems; cancelled loads (e.g. a link we sent to Safari) are not failures.
        let offline: Set<Int> = [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorCannotFindHost,
                                 NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed]
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain, offline.contains(nsError.code) else { return }
        let html = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="margin:0;height:100vh;display:grid;place-items:center;background:#12151f;color:#ece6d8;font:18px -apple-system,sans-serif">
        <div style="text-align:center;padding:24px"><p>Riff Room needs the internet to start.</p>
        <p><a href="https://pianoriffs.app/" style="color:#e2b25c;font-weight:700">Try again</a></p></div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

/// Avoids a retain cycle between WKUserContentController and the view controller.
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
