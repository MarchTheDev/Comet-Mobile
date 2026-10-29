//
//  CometViewController.swift
//  Comet for iOS
//
//  Hosts the web view, starts the loopback server, and keeps the page on its
//  own origin: links that would navigate the app somewhere else are handed to
//  Safari instead.
//

import UIKit
import WebKit

enum CometTheme {
    static let background = UIColor(red: 16.0 / 255.0, green: 22.0 / 255.0, blue: 28.0 / 255.0, alpha: 1)
}

final class CometViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    /// The page's origin — and therefore everything Comet remembers — is the
    /// host and port together, so the first port is the one that matters. The
    /// rest only exist so a taken port cannot stop the app from starting.
    private static let candidatePorts: [UInt16] = [47823, 47824, 47825, 47826]

    private var webView: WKWebView!
    private var baseURL: URL?
    private var bottomConstraint: NSLayoutConstraint?
    private var overlay: UIView?
    private var loadAttempt = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = CometTheme.background

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statusBarStyleChanged),
            name: .cometStatusBarStyleChanged,
            object: nil
        )

        webView.isOpaque = false
        webView.backgroundColor = CometTheme.background
        webView.scrollView.backgroundColor = CometTheme.background
        // Comet keeps its own history; a system swipe would step outside it.
        webView.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) {
            // Attach Safari's Web Inspector when a cable is connected.
            webView.isInspectable = true
        }

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
        bottomConstraint = webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        bottomConstraint?.isActive = true
        self.webView = webView

        UIHost.presenter = self
        addOverlay()
        observeKeyboard()
        startServer(attempt: 0)
    }

    /// The page reports its theme through `plugin:comet|status_bar`; this is
    /// only the reader. Before the page says anything the dark theme's light
    /// clock is the safer guess, because that is Comet's default.
    override var preferredStatusBarStyle: UIStatusBarStyle {
        Appearance.prefersLightStatusBar ? .lightContent : .darkContent
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Server and page

    private func startServer(attempt: Int) {
        guard attempt < Self.candidatePorts.count else {
            showFailure("Comet couldn't start its local bridge.")
            return
        }
        AppServices.shared.server.start(port: Self.candidatePorts[attempt]) { [weak self] port in
            DispatchQueue.main.async { self?.load(port: port) }
        } failed: { [weak self] _ in
            DispatchQueue.main.async { self?.startServer(attempt: attempt + 1) }
        }
    }

    private func load(port: UInt16) {
        let base = "http://127.0.0.1:\(port)"
        guard let url = URL(string: base + "/") else {
            showFailure("Comet couldn't address its local bridge.")
            return
        }
        baseURL = url
        installShim(base: base)
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    /// Everything the page needs before its own first line runs, in order:
    ///
    ///  1. the bridge, because Comet's module scope asks `isTauri()` immediately;
    ///  2. the mobile stylesheet and the `comet-mobile` class, so the desktop
    ///     layout is never painted at all — a flash of a sidebar squeezed onto
    ///     a phone is exactly what this build exists to remove;
    ///  3. the mobile shell, after the document, where it can wait for React.
    private func installShim(base: String) {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()

        if let url = Bundle.main.url(forResource: "shim", withExtension: "js"),
           let template = try? String(contentsOf: url, encoding: .utf8) {
            let source = template.replacingOccurrences(of: "__COMET_BASE__", with: base)
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        if let cssScript = mobileStyleScript() {
            controller.addUserScript(WKUserScript(source: cssScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        if let url = Bundle.main.url(forResource: "mobile", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
    }

    /// The stylesheet travels inside the script rather than as a linked file:
    /// it applies before the body exists, which is the whole point of doing it
    /// at document start, and it cannot race the page.
    private func mobileStyleScript() -> String? {
        guard let cssURL = Bundle.main.url(forResource: "mobile", withExtension: "css"),
              let css = try? String(contentsOf: cssURL, encoding: .utf8) else {
            return nil
        }
        let encoded = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
        return """
        (function () {
          try {
            var root = document.documentElement;
            root.classList.add("comet-mobile");
            var style = document.createElement("style");
            style.id = "comet-mobile-styles";
            style.textContent = `\(encoded)`;
            (document.head || root).appendChild(style);
          } catch (error) { /* a broken stylesheet must not stop the app */ }
        })();
        """
    }

    @objc private func statusBarStyleChanged() {
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - Launch overlay

    private func addOverlay() {
        let cover = UIView(frame: .zero)
        cover.translatesAutoresizingMaskIntoConstraints = false
        cover.backgroundColor = CometTheme.background

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        spinner.startAnimating()

        let label = UILabel(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Comet"
        label.textColor = UIColor(white: 1, alpha: 0.7)
        label.font = .systemFont(ofSize: 17, weight: .medium)

        cover.addSubview(spinner)
        cover.addSubview(label)
        view.addSubview(cover)
        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: view.topAnchor),
            cover.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            cover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: cover.centerYAnchor, constant: -18),
            label.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12)
        ])
        overlay = cover
    }

    private func hideOverlay() {
        guard let overlay else { return }
        self.overlay = nil
        UIView.animate(withDuration: 0.25, animations: { overlay.alpha = 0 }) { _ in
            overlay.removeFromSuperview()
        }
    }

    private func showFailure(_ message: String) {
        hideOverlay()
        let label = UILabel(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = UIColor(white: 1, alpha: 0.75)
        label.font = .systemFont(ofSize: 15)
        label.text = message + "\n\nClose and reopen Comet to try again."
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8)
        ])
    }

    // MARK: - Keyboard

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let end = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let frame = view.convert(end, from: nil)
        let overlap = max(0, view.bounds.maxY - frame.minY)
        // The safe area already accounts for the home indicator, which the
        // keyboard covers, so only the extra height has to come off the web view.
        let shrink = max(0, overlap - view.safeAreaInsets.bottom)
        bottomConstraint?.constant = -shrink
        UIView.animate(withDuration: 0.22) { self.view.layoutIfNeeded() }
    }

    // MARK: - Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme.isEmpty || scheme == "about" || scheme == "data" || scheme == "blob" || scheme == "javascript" {
            decisionHandler(.allow)
            return
        }
        if let base = baseURL, url.host == base.host, url.port == base.port {
            decisionHandler(.allow)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if !isMainFrame {
            // Embedded players and previews load their own frames.
            if scheme == "http" || scheme == "https" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
            return
        }
        if scheme == "http" || scheme == "https" || scheme == "mailto" {
            UIApplication.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            UIApplication.shared.open(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadAttempt = 0
        hideOverlay()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        retryAfterFailureIfUseful(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        retryAfterFailureIfUseful(error)
    }

    private func retryAfterFailureIfUseful(_ error: Error) {
        let code = (error as NSError).code
        // A cancelled load is the app telling itself to stop; anything else may
        // be the listener not being ready yet, which is worth one more try.
        guard code != NSURLErrorCancelled else { return }
        guard loadAttempt < 3, let url = baseURL else {
            showFailure("Comet couldn't load its interface.")
            return
        }
        loadAttempt += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.webView.load(URLRequest(url: url))
        }
    }

    /// iOS can reclaim the web content process while the app is in the
    /// background. The page is stateless beyond its own storage, so reloading is
    /// the whole recovery.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let url = baseURL {
            webView.load(URLRequest(url: url))
        }
    }
}
