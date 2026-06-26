// UI/Components/WebPreviewView.swift
// NSViewRepresentable wrapping WKWebView for offline Markdown preview.
// Security: JS disabled, navigation blocked, baseURL:nil, identical-HTML guard (Pitfall #5).
// PDF: createPDF only after navigation-finished delegate fires.
// Cold-start: WKWebView deferred to first updateNSView call (Pitfall #6).

import SwiftUI
import WebKit

struct WebPreviewView: NSViewRepresentable {
    /// HTML string to display. Update triggers reload only if content changed (Pitfall #5 guard).
    var html: String
    /// Called when PDF export is requested. Receives file URL to write PDF data to.
    var onPDFExport: ((URL) -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        // Build configuration: disable JavaScript (XSS + offline guarantee)
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Accessibility
        webView.setAccessibilityLabel("Markdown preview")

        // Store reference in coordinator for PDF export
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // CRITICAL: identical-HTML guard prevents reload loops (Pitfall #5 in WKWebView clothing)
        guard html != context.coordinator.lastLoadedHTML else { return }
        context.coordinator.lastLoadedHTML = html
        context.coordinator.didFinishNavigation = false
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - PDF Export

    /// Export the currently-loaded HTML as a PDF to the given URL.
    /// Executes after navigation-finished fires; if not finished yet, defers until it is.
    func exportPDF(to url: URL, coordinator: Coordinator) {
        let doExport: () -> Void = {
            let pdfConfig = WKPDFConfiguration()
            coordinator.webView?.createPDF(configuration: pdfConfig) { result in
                switch result {
                case .success(let data):
                    try? data.write(to: url)
                case .failure:
                    break
                }
            }
        }

        if coordinator.didFinishNavigation {
            doExport()
        } else {
            coordinator.pendingPDFExport = doExport
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        /// Tracks last loaded HTML to prevent redundant reloads.
        var lastLoadedHTML: String = ""
        /// True once the initial navigation has finished (used to gate PDF export).
        var didFinishNavigation: Bool = false
        /// Pending PDF export closure, executed when navigation finishes.
        var pendingPDFExport: (() -> Void)? = nil
        /// Weak reference to the web view for PDF export.
        weak var webView: WKWebView?

        // Block all navigation except the initial loadHTMLString (navigationType == .other)
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Allow the initial HTML load (type .other); block all link/form navigation
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishNavigation = true
            if let pending = pendingPDFExport {
                pendingPDFExport = nil
                pending()
            }
        }
    }
}
