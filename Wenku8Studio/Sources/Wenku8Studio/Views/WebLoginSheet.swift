import SwiftUI
import WebKit
import Wenku8Core

struct WebLoginSheet: View {
    @EnvironmentObject var vm: StudioViewModel
    @State private var currentURLString: String = ""
    @State private var webViewRef: WKWebView?
    @State private var statusHint: String = "请在下方网页登录你的 wenku8 账号，登录成功后点击右上角「提取 Cookie」。"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("轻小说文库 · 内置登录获取 Cookie")
                        .font(.headline)
                    Text(statusHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("刷新") {
                            webViewRef?.reload()
                        }
                        .buttonStyle(.glass)

                        Button("取消") {
                            vm.showWebLoginSheet = false
                        }
                        .buttonStyle(.glass)

                        Button("提取 Cookie 并验证") {
                            extractCookies()
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
            .padding()
            .background(.bar)

            Divider()

            Wenku8WebView(
                initialURL: URL(string: "\(Wenku8Client.normalizeBaseURL(vm.baseURL))/login.php")!,
                currentURLString: $currentURLString,
                webViewRef: $webViewRef
            )
        }
        .frame(minWidth: 780, minHeight: 560)
    }

    private func extractCookies() {
        guard let store = webViewRef?.configuration.websiteDataStore.httpCookieStore else {
            statusHint = "无法读取浏览器 Cookie 存储"
            return
        }
        store.getAllCookies { cookies in
            let relevant = cookies.filter { cookie in
                let domain = cookie.domain.lowercased()
                return domain.contains("wenku8")
            }
            if relevant.isEmpty {
                DispatchQueue.main.async {
                    statusHint = "尚未检测到 wenku8 Cookie，请确认已完成登录。"
                }
                return
            }
            let cookieString = relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            DispatchQueue.main.async {
                vm.applyWebLoginCookie(cookieString)
            }
        }
    }
}

private struct Wenku8WebView: NSViewRepresentable {
    let initialURL: URL
    @Binding var currentURLString: String
    @Binding var webViewRef: WKWebView?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        webView.load(URLRequest(url: initialURL))
        DispatchQueue.main.async {
            self.webViewRef = webView
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: Wenku8WebView

        init(parent: Wenku8WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let urlStr = webView.url?.absoluteString ?? ""
            parent.currentURLString = urlStr
            if urlStr.contains("login.php") {
                // Default session persistence to 1 month so PHPSESSID/jieqiUserInfo doesn't expire immediately
                webView.evaluateJavaScript("""
                (function() {
                    var sel = document.querySelector("select[name='usecookie']");
                    if (sel && sel.value === "0") {
                        for (var i = 0; i < sel.options.length; i++) {
                            if (sel.options[i].value === "2592000") {
                                sel.value = "2592000";
                                break;
                            }
                        }
                    }
                })();
                """)
            }
        }
    }
}
