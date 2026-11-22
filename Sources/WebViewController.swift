import UIKit
import WebKit
import UniformTypeIdentifiers

final class WebViewController: UIViewController {

    private static let pickerHandlerName = "pickFile"

    private var webView: WKWebView!

    /// 下载中的文件：WKDownload -> 临时落盘地址
    private var downloadTargets: [ObjectIdentifier: URL] = [:]

    /// 注入到页面里的桥接脚本：劫持 <input type="file"> 的点击，改走原生文档选择器
    private static let bridgeScript = """
    (function () {
      if (window.__gdouBridgeInstalled) { return; }
      window.__gdouBridgeInstalled = true;

      window.__gdouReceiveFile = function (name, b64, mime) {
        try {
          var bin = atob(b64);
          var u = new Uint8Array(bin.length);
          for (var i = 0; i < bin.length; i++) { u[i] = bin.charCodeAt(i); }
          var file = new File([u], name, { type: mime || 'application/octet-stream' });
          var dt = new DataTransfer();
          dt.items.add(file);
          var input = document.getElementById('fileInput');
          if (!input) { alert('页面里找不到文件输入框'); return; }
          input.files = dt.files;
          input.dispatchEvent(new Event('change', { bubbles: true }));
        } catch (err) {
          alert('读取文件失败：' + err.message);
        }
      };

      document.addEventListener('click', function (e) {
        var t = e.target;
        if (t && t.id === 'fileInput') {
          e.preventDefault();
          var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(pickerHandlerName);
          if (bridge) { bridge.postMessage('pick'); }
        }
      }, true);
    })();
    """

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupWebView()
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.pickerHandlerName)
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SchemeHandler(root: Bundle.main.bundleURL), forURLScheme: SchemeHandler.scheme)
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let controller = WKUserContentController()
        controller.add(self, name: Self.pickerHandlerName)
        controller.addUserScript(WKUserScript(source: Self.bridgeScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        config.userContentController = controller

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.isOpaque = false
        web.backgroundColor = .white
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        webView = web

        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            web.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let url = URL(string: "\(SchemeHandler.scheme)://app/index.html")!
        web.load(URLRequest(url: url))
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }
}

// MARK: - 原生文件选择

extension WebViewController: WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == Self.pickerHandlerName else { return }
        presentFilePicker()
    }

    private func presentFilePicker() {
        let types: [UTType] = [.pdf, .json, .plainText, .commaSeparatedText]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
}

extension WebViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent
            deliver(fileData: data, name: name)
        } catch {
            presentAlert(title: "读取失败", message: error.localizedDescription)
        }
    }

    private func deliver(fileData: Data, name: String) {
        let b64 = fileData.base64EncodedString()
        let mime = Self.mimeType(for: name)
        let js = "window.__gdouReceiveFile(\(Self.jsLiteral(name)), \(Self.jsLiteral(b64)), \(Self.jsLiteral(mime)));"
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                self.presentAlert(title: "交给页面失败", message: error.localizedDescription)
            }
        }
    }
}

// MARK: - 导航与下载

extension WebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        // 高德导航等外部链接交给系统
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
}

// MARK: - 下载落盘 + 分享

extension WebViewController: WKDownloadDelegate {

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdou-download-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            completionHandler(nil)
            return
        }
        var name = suggestedFilename.isEmpty ? "gdou_schedule.json" : suggestedFilename
        if !name.contains(".") { name += ".json" }
        let target = dir.appendingPathComponent(name)
        downloadTargets[ObjectIdentifier(download)] = target
        completionHandler(target)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadTargets.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadTargets.removeValue(forKey: ObjectIdentifier(download))
        presentAlert(title: "导出失败", message: error.localizedDescription)
    }
}

// MARK: - JS 弹窗

extension WebViewController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }
}

// MARK: - 工具

extension WebViewController {

    fileprivate func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    static func mimeType(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "json": return "application/json"
        case "txt", "md": return "text/plain"
        case "csv": return "text/csv"
        default: return "application/octet-stream"
        }
    }

    static func jsLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else {
            return "\"\""
        }
        // ["abc"] -> "abc"
        return String(json.dropFirst().dropLast())
    }
}
