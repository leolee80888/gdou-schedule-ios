import Foundation
import WebKit

/// 用自定义 scheme 加载内置网页，给页面一个稳定的 origin，
/// 这样 localStorage（课表数据）才能可靠持久化，file:// 下会被当成不透明来源。
final class SchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "gdou"

    private let root: URL

    init(root: URL) {
        self.root = root
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(Self.error(400))
            return
        }

        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let fileURL = root.appendingPathComponent(String(path.dropFirst()))

        // 只允许读取 App 包内文件
        let base = root.standardizedFileURL.path
        guard fileURL.standardizedFileURL.path.hasPrefix(base),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(Self.error(404))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: fileURL.pathExtension),
                "Content-Length": String(data.count),
                "Cache-Control": "no-cache",
                "Access-Control-Allow-Origin": "*"
            ]
        )

        if let response {
            urlSchemeTask.didReceive(response)
        }
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // 单文件页面，无需中断
    }

    private static func error(_ code: Int) -> NSError {
        NSError(domain: "GdouSchedule", code: code,
                userInfo: [NSLocalizedDescriptionKey: "资源不存在（\(code)）"])
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "txt": return "text/plain; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        default: return "application/octet-stream"
        }
    }
}
