import AppKit
import CoreFoundation
import Foundation

public enum Wenku8Error: LocalizedError, Sendable {
    case invalidBookInput(String)
    case cloudflareBlocked(String)
    case httpError(Int, String)
    case parseError(String)
    case networkError(String)
    case loginRequired(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBookInput(let msg): return "无效输入：\(msg)"
        case .cloudflareBlocked(let url): return "访问受限（Cloudflare 拦截）：\(url)"
        case .httpError(let code, let url): return "HTTP \(code) 请求失败：\(url)"
        case .parseError(let msg): return "页面解析失败：\(msg)"
        case .networkError(let msg): return "网络请求失败：\(msg)"
        case .loginRequired(let msg): return msg
        }
    }
}

public actor Wenku8Client {
    public static let officialMirrors = [
        "https://www.wenku8.cc",
        "https://www.wenku8.net",
    ]
    private static let cloudflareMarkers = [
        "used Cloudflare to restrict access",
        "Just a moment...",
        "Attention Required! | Cloudflare",
    ]
    private static let colorKeywords: Set<String> = ["插图", "彩页", "插画"]

    private var preferredBaseURL: String
    private var customCookie: String
    private var requestTimeout: TimeInterval
    private var politeDelaySeconds: Double
    private let session: URLSession

    public init(
        baseURL: String = "https://www.wenku8.cc",
        cookie: String = "",
        timeout: TimeInterval = 15,
        politeDelaySeconds: Double = 0.25
    ) {
        self.preferredBaseURL = Self.normalizeBaseURL(baseURL)
        self.customCookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        self.requestTimeout = timeout
        self.politeDelaySeconds = politeDelaySeconds

        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 16
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = max(30, timeout * 2)
        self.session = URLSession(configuration: config)
    }

    public func updateSettings(
        baseURL: String,
        cookie: String,
        timeout: TimeInterval,
        politeDelaySeconds: Double
    ) {
        self.preferredBaseURL = Self.normalizeBaseURL(baseURL)
        self.customCookie = Self.normalizeCookie(cookie)
        self.requestTimeout = timeout
        self.politeDelaySeconds = politeDelaySeconds
    }

    public static func normalizeCookie(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("cookie:") {
            cleaned = String(cleaned.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        cleaned = cleaned
            .replacingOccurrences(of: "\r\n", with: "; ")
            .replacingOccurrences(of: "\n", with: "; ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        return cleaned
    }

    public struct CookieDiagnostic: Sendable {
        public let isLikelyValidFormat: Bool
        public let isForeignSiteCookie: Bool
        public let message: String
        public let normalizedCookie: String
    }

    public static func diagnoseCookieFormat(_ raw: String) -> CookieDiagnostic {
        let norm = normalizeCookie(raw)
        if norm.isEmpty {
            return CookieDiagnostic(
                isLikelyValidFormat: false,
                isForeignSiteCookie: false,
                message: "当前未配置 Cookie。可使用「网页登录自动获取」或从浏览器复制 wenku8.cc 的 Cookie。",
                normalizedCookie: ""
            )
        }

        let foreignMarkers = ["MUID=", "ANON=", "NAP=", "SRCHD=", "_EDGE_S="]
        if foreignMarkers.contains(where: { norm.contains($0) }) && !norm.contains("jieqiUserInfo") {
            return CookieDiagnostic(
                isLikelyValidFormat: false,
                isForeignSiteCookie: true,
                message: "检测到这是微软/Bing 网站的 Cookie（包含 MUID/ANON/NAP），不是轻小说文库（wenku8）的 Cookie。请在 wenku8.cc 登录后再复制，或直接点「网页登录自动获取」。",
                normalizedCookie: norm
            )
        }

        let pairs = norm.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains("=") }
        if pairs.isEmpty {
            return CookieDiagnostic(
                isLikelyValidFormat: false,
                isForeignSiteCookie: false,
                message: "Cookie 格式不正确，应为 key1=value1; key2=value2 形式。",
                normalizedCookie: norm
            )
        }

        let hasWenku8Session = norm.contains("jieqiUserInfo") || norm.contains("PHPSESSID") || norm.contains("jieqiVisitInfo")
        if !hasWenku8Session {
            return CookieDiagnostic(
                isLikelyValidFormat: false,
                isForeignSiteCookie: false,
                message: "未检测到 wenku8 登录字段（通常包含 jieqiUserInfo 或 PHPSESSID），可能来自其他站点或未登录状态。",
                normalizedCookie: norm
            )
        }

        return CookieDiagnostic(
            isLikelyValidFormat: true,
            isForeignSiteCookie: false,
            message: "Cookie 格式符合 wenku8 规范（共 \(pairs.count) 个字段），可点击「测试有效性」验证登录状态。",
            normalizedCookie: norm
        )
    }

    public struct CookieVerifyResult: Sendable {
        public let isLoggedIn: Bool
        public let message: String
        public let sampleCount: Int
    }

    public func verifyCookieLive(cookie: String, baseURL: String? = nil) async -> CookieVerifyResult {
        let diag = Self.diagnoseCookieFormat(cookie)
        if diag.normalizedCookie.isEmpty || diag.isForeignSiteCookie {
            return CookieVerifyResult(isLoggedIn: false, message: diag.message, sampleCount: 0)
        }
        let saved = self.customCookie
        self.customCookie = diag.normalizedCookie
        defer { self.customCookie = saved }

        let base = Self.normalizeBaseURL(baseURL ?? preferredBaseURL)
        do {
            let html = try await fetchHTML(urlString: "\(base)/modules/article/toplist.php?sort=allvisit", referer: base, delay: false)
            if html.contains("本站正式关闭") || html.contains("用户登录") && !html.contains("退出登录") {
                return CookieVerifyResult(isLoggedIn: false, message: "Cookie 无效或已过期（站点仍返回未登录页面），请重新登录获取。", sampleCount: 0)
            }
            let items = Self.parseAuthorBooksPage(html: html)
            return CookieVerifyResult(
                isLoggedIn: true,
                message: "Cookie 验证成功！已成功访问会员榜单（解析到 \(items.count) 条榜单书籍）。",
                sampleCount: items.count
            )
        } catch {
            return CookieVerifyResult(isLoggedIn: false, message: "验证请求失败：\(error.localizedDescription)", sampleCount: 0)
        }
    }

    public static func normalizeBaseURL(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }
        if cleaned.isEmpty {
            return "https://www.wenku8.cc"
        }
        if !cleaned.hasPrefix("http://") && !cleaned.hasPrefix("https://") {
            cleaned = "https://\(cleaned)"
        }
        return cleaned
    }

    public static func extractBookId(from rawInput: String) -> String {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.allSatisfy(\.isNumber) {
            return trimmed
        }
        let patterns = [
            #"/book/(\d+)"#,
            #"/novel/\d+/(\d+)"#,
            #"aid=(\d+)"#,
            #"id=(\d+)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed)
            {
                return String(trimmed[range])
            }
        }
        return ""
    }

    public static func decodeGB18030(_ data: Data) -> String {
        let cfEnc = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
        let gbEnc = String.Encoding(rawValue: nsEnc)
        if let str = String(data: data, encoding: gbEnc) {
            return str
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(decoding: data, as: UTF8.self)
    }

    public static func encodeGBKQuery(_ text: String) -> String {
        let cfEnc = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
        let gbEnc = String.Encoding(rawValue: nsEnc)
        guard let data = text.data(using: gbEnc) else {
            return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        }
        return data.map { byte in
            if (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) {
                return String(UnicodeScalar(byte))
            }
            return String(format: "%%%02X", byte)
        }.joined()
    }

    private func buildRequest(url: URL, referer: String) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: requestTimeout)
        req.httpShouldHandleCookies = false
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue(referer, forHTTPHeaderField: "Referer")
        if !customCookie.isEmpty {
            req.setValue(customCookie, forHTTPHeaderField: "Cookie")
        }
        return req
    }

    public func fetchHTML(urlString: String, referer: String? = nil, delay: Bool = true) async throws -> String {
        if delay && politeDelaySeconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(politeDelaySeconds * 1_000_000_000))
        }
        guard let url = URL(string: urlString) else {
            throw Wenku8Error.networkError("非法 URL：\(urlString)")
        }

        let ref = referer ?? preferredBaseURL
        let req = buildRequest(url: url, referer: ref)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Wenku8Error.networkError("\(urlString): \(error.localizedDescription)")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        let text = Self.decodeGB18030(data)
        if status == 403 || Self.cloudflareMarkers.contains(where: { text.contains($0) }) {
            throw Wenku8Error.cloudflareBlocked(urlString)
        }
        if status >= 400 {
            throw Wenku8Error.httpError(status, urlString)
        }
        return text
    }

    public func fetchBookDetail(
        rawInput: String,
        onLog: (@Sendable (String) -> Void)? = nil
    ) async throws -> BookDetail {
        let bookId = Self.extractBookId(from: rawInput)
        guard !bookId.isEmpty else {
            throw Wenku8Error.invalidBookInput("请输入有效的数字书号或 wenku8 书籍链接")
        }

        var candidates = [preferredBaseURL]
        if Self.officialMirrors.contains(preferredBaseURL) {
            for m in Self.officialMirrors where !candidates.contains(m) {
                candidates.append(m)
            }
        }

        var lastError: Error = Wenku8Error.networkError("未知错误")
        for (idx, candidateBase) in candidates.enumerated() {
            try Task.checkCancellation()
            if idx > 0 {
                onLog?("站点 \(candidates[idx - 1]) 访问受限，自动切换备用域名：\(candidateBase)")
            }
            do {
                let bookURL = "\(candidateBase)/book/\(bookId).htm"
                let mainHTML = try await fetchHTML(urlString: bookURL, referer: candidateBase, delay: false)
                let parsedBook = try Self.parseBookPage(html: mainHTML, bookURL: bookURL, baseURL: candidateBase)

                let catalogHTML = try await fetchHTML(urlString: parsedBook.catalogURL, referer: bookURL, delay: true)
                let (catalogTitle, catalogAuthor, volumes) = try Self.parseCatalogPage(
                    html: catalogHTML,
                    catalogURL: parsedBook.catalogURL
                )

                return BookDetail(
                    bookId: bookId,
                    baseURL: candidateBase,
                    title: catalogTitle.isEmpty ? parsedBook.title : catalogTitle,
                    author: catalogAuthor.isEmpty ? parsedBook.author : catalogAuthor,
                    publisher: parsedBook.publisher,
                    status: parsedBook.status,
                    lastUpdated: parsedBook.lastUpdated,
                    wordCount: parsedBook.wordCount,
                    popularity: parsedBook.popularity,
                    latestChapter: parsedBook.latestChapter,
                    tags: parsedBook.tags,
                    description: parsedBook.description,
                    coverURL: parsedBook.coverURL,
                    catalogURL: parsedBook.catalogURL,
                    volumes: volumes,
                    recommendations: parsedBook.recommendations
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    public func fetchChapterContent(chapter: ChapterItem, baseURL: String? = nil) async throws -> ChapterContent {
        let referer = baseURL ?? preferredBaseURL
        let html = try await fetchHTML(urlString: chapter.url, referer: referer, delay: true)
        return try Self.parseChapterContent(html: html, chapter: chapter)
    }

    public func fetchReviews(bookId: String, baseURL: String? = nil) async throws -> [BookReview] {
        let base = Self.normalizeBaseURL(baseURL ?? preferredBaseURL)
        let url = "\(base)/modules/article/reviews.php?aid=\(bookId)"
        let html = try await fetchHTML(urlString: url, referer: "\(base)/book/\(bookId).htm", delay: false)
        return Self.parseReviewsPage(html: html, baseURL: base)
    }

    public func fetchReviewThread(reviewURL: String, baseURL: String? = nil) async throws -> [ReviewPost] {
        let base = Self.normalizeBaseURL(baseURL ?? preferredBaseURL)
        let fullURL = Self.resolveURL(reviewURL, relativeTo: base)
        let html = try await fetchHTML(urlString: fullURL, referer: base, delay: false)
        return Self.parseReviewThreadPage(html: html, baseURL: base)
    }

    public func fetchAuthorBooks(author: String, baseURL: String? = nil) async throws -> [AuthorBookItem] {
        let base = Self.normalizeBaseURL(baseURL ?? preferredBaseURL)
        let encodedAuthor = Self.encodeGBKQuery(author)
        let url = "\(base)/modules/article/authorarticle.php?author=\(encodedAuthor)"
        let html = try await fetchHTML(urlString: url, referer: base, delay: false)
        return Self.parseAuthorBooksPage(html: html)
    }

    public func searchBooks(query: String, scope: SearchScope, baseURL: String? = nil) async throws -> [AuthorBookItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let base = Self.normalizeBaseURL(baseURL ?? preferredBaseURL)

        switch scope {
        case .bookId:
            let detail = try await fetchBookDetail(rawInput: trimmed)
            return [AuthorBookItem(
                id: detail.bookId,
                title: detail.title,
                author: detail.author,
                category: detail.publisher,
                updatedAt: detail.lastUpdated,
                wordCount: detail.wordCount,
                status: detail.status,
                popularity: detail.popularity,
                tags: detail.tags,
                summary: detail.description,
                coverURL: detail.coverURL
            )]
        case .author:
            return try await fetchAuthorBooks(author: trimmed, baseURL: base)
        case .articleName:
            let encoded = Self.encodeGBKQuery(trimmed)
            let url = "\(base)/modules/article/search.php?searchtype=articlename&searchkey=\(encoded)"
            let html = try await fetchHTML(urlString: url, referer: base, delay: false)
            if html.trimmingCharacters(in: .whitespacesAndNewlines) == "Welcome" || html.contains("本站正式关闭") {
                throw Wenku8Error.loginRequired("按书名全站搜索需要 wenku8 登录 Cookie，请先在「设置与拼装」中登录获取或填写 Cookie（按作者名/书号搜索可免登录使用）。")
            }
            let list = Self.parseAuthorBooksPage(html: html)
            if !list.isEmpty {
                return list
            }
            // Single-hit search redirects to /book/{id}.htm
            if let singleBook = try? Self.parseBookPage(html: html, bookURL: url, baseURL: base) {
                let singleId = Self.extractBookId(from: singleBook.catalogURL)
                if !singleId.isEmpty {
                    return [AuthorBookItem(
                        id: singleId,
                        title: singleBook.title,
                        author: singleBook.author,
                        category: singleBook.publisher,
                        updatedAt: singleBook.lastUpdated,
                        wordCount: singleBook.wordCount,
                        status: singleBook.status,
                        popularity: singleBook.popularity,
                        tags: singleBook.tags,
                        summary: singleBook.description,
                        coverURL: singleBook.coverURL
                    )]
                }
            }
            return []
        }
    }

    public func fetchDiscoveryBooks(listPath: String, baseURL: String? = nil) async throws -> [AuthorBookItem] {
        let base = Self.normalizeBaseURL(baseURL ?? preferredBaseURL)
        let url = listPath.hasPrefix("http") ? listPath : "\(base)\(listPath)"
        let html = try await fetchHTML(urlString: url, referer: base, delay: false)
        if html.contains("本站正式关闭") {
            throw Wenku8Error.loginRequired("全站榜单与分类专区需要 wenku8 登录 Cookie，请先前往「设置与拼装」一键网页登录或填写 Cookie。")
        }
        return Self.parseAuthorBooksPage(html: html)
    }

    public func downloadSingleImage(urlString: String, referer: String? = nil) async throws -> DownloadedImageAsset {
        var candidateURLs: [String] = []
        if urlString.hasPrefix("http://") {
            candidateURLs.append("https://" + urlString.dropFirst("http://".count))
        }
        candidateURLs.append(urlString)

        var lastError: Error = Wenku8Error.networkError("图片下载失败")
        for targetStr in candidateURLs {
            guard let url = URL(string: targetStr) else { continue }
            for attempt in 1...2 {
                try Task.checkCancellation()
                do {
                    let req = buildRequest(url: url, referer: referer ?? preferredBaseURL)
                    let (data, response) = try await session.data(for: req)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                    guard status == 200, !data.isEmpty else {
                        throw Wenku8Error.httpError(status, targetStr)
                    }
                    let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                    if contentType.contains("text/html") && !Self.looksLikeImageBytes(data) {
                        throw Wenku8Error.parseError("图片返回内容为 HTML：\(targetStr)")
                    }
                    let (ext, mime) = Self.detectImageFormat(data: data, urlString: targetStr)
                    let (w, h) = Self.measureImageSize(data: data)
                    return DownloadedImageAsset(
                        url: urlString,
                        data: data,
                        fileExtension: ext,
                        mimeType: mime,
                        width: w,
                        height: h
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = error
                    if attempt < 2 {
                        try await Task.sleep(nanoseconds: 400_000_000)
                    }
                }
            }
        }
        throw lastError
    }

    public func downloadImages(
        urls: [String],
        referer: String? = nil,
        maxConcurrency: Int = 8,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [String: DownloadedImageAsset] {
        let uniqueURLs = Array(NSOrderedSet(array: urls).compactMap { $0 as? String })
        if uniqueURLs.isEmpty { return [:] }

        let limit = max(1, min(16, maxConcurrency))
        let total = uniqueURLs.count
        var result: [String: DownloadedImageAsset] = [:]
        var completed = 0

        try await withThrowingTaskGroup(of: (String, DownloadedImageAsset?).self) { group in
            var nextIndex = 0
            for _ in 0..<min(limit, total) {
                let url = uniqueURLs[nextIndex]
                nextIndex += 1
                group.addTask {
                    try Task.checkCancellation()
                    let asset = try? await self.downloadSingleImage(urlString: url, referer: referer)
                    return (url, asset)
                }
            }

            while let (url, asset) = try await group.next() {
                try Task.checkCancellation()
                if let asset {
                    result[url] = asset
                }
                completed += 1
                onProgress?(completed, total)

                if nextIndex < total {
                    let nextURL = uniqueURLs[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        try Task.checkCancellation()
                        let nextAsset = try? await self.downloadSingleImage(urlString: nextURL, referer: referer)
                        return (nextURL, nextAsset)
                    }
                }
            }
        }
        return result
    }

    // MARK: - Static HTML Parsers

    public struct ParsedBookPage {
        public let title: String
        public let author: String
        public let publisher: String
        public let status: String
        public let lastUpdated: String
        public let wordCount: String
        public let popularity: String
        public let latestChapter: String
        public let tags: [String]
        public let description: String
        public let coverURL: String
        public let catalogURL: String
        public let recommendations: [RecommendedBook]
    }

    public static func parseBookPage(html: String, bookURL: String, baseURL: String) throws -> ParsedBookPage {
        let doc = try XMLDocument(xmlString: html, options: [.documentTidyHTML])
        let contentNode = (try? doc.nodes(forXPath: "//div[@id='content']").first) ?? doc.rootElement()

        var title = ""
        if let bNode = (try? contentNode?.nodes(forXPath: ".//table//b").first) {
            title = bNode.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        var catalogURL = ""
        if let aNodes = try? contentNode?.nodes(forXPath: ".//a[@href]") as? [XMLElement] {
            for a in aNodes {
                let txt = a.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if txt == "小说目录" || txt.contains("小说目录"),
                   let href = a.attribute(forName: "href")?.stringValue {
                    catalogURL = resolveURL(href, relativeTo: bookURL)
                    break
                }
            }
        }
        if catalogURL.isEmpty {
            throw Wenku8Error.parseError("未能从书籍主页找到“小说目录”链接")
        }

        var publisher = ""
        var author = ""
        var status = ""
        var lastUpdated = ""
        var wordCount = ""
        var popularity = ""
        var latestChapter = ""
        var tags: [String] = []
        var description = ""

        if let tdNodes = try? contentNode?.nodes(forXPath: ".//td") as? [XMLElement] {
            for td in tdNodes {
                let text = td.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.hasPrefix("文库分类：") {
                    publisher = String(text.dropFirst("文库分类：".count)).trimmingCharacters(in: .whitespaces)
                } else if text.hasPrefix("小说作者：") {
                    author = String(text.dropFirst("小说作者：".count)).trimmingCharacters(in: .whitespaces)
                } else if text.hasPrefix("文章状态：") {
                    status = String(text.dropFirst("文章状态：".count)).trimmingCharacters(in: .whitespaces)
                } else if text.hasPrefix("最后更新：") {
                    lastUpdated = String(text.dropFirst("最后更新：".count)).trimmingCharacters(in: .whitespaces)
                } else if text.hasPrefix("全文长度：") {
                    wordCount = String(text.dropFirst("全文长度：".count)).trimmingCharacters(in: .whitespaces)
                }
            }
        }

        if let spans = try? contentNode?.nodes(forXPath: ".//span") as? [XMLElement] {
            for (idx, span) in spans.enumerated() {
                let text = span.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.hasPrefix("作品Tags：") {
                    let rawTags = String(text.dropFirst("作品Tags：".count))
                    tags = rawTags.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                } else if text.hasPrefix("作品热度：") {
                    popularity = String(text.dropFirst("作品热度：".count)).trimmingCharacters(in: .whitespaces)
                } else if text == "最近章节：" && idx + 1 < spans.count {
                    latestChapter = spans[idx + 1].stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                } else if text == "内容简介：" && idx + 1 < spans.count {
                    description = spans[idx + 1].stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
            }
        }

        var coverURL = ""
        if let imgs = try? contentNode?.nodes(forXPath: ".//img[@src]") as? [XMLElement] {
            for img in imgs {
                let src = img.attribute(forName: "src")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if src.contains("/image/") || src.contains("/files/article/") {
                    coverURL = resolveURL(src, relativeTo: bookURL)
                    break
                }
            }
            if coverURL.isEmpty, let firstSrc = imgs.first?.attribute(forName: "src")?.stringValue {
                coverURL = resolveURL(firstSrc, relativeTo: bookURL)
            }
        }

        var recommendations: [RecommendedBook] = []
        var seenRecIds = Set<String>()
        if let recLinks = try? contentNode?.nodes(forXPath: ".//a[contains(@href, '/book/')]") as? [XMLElement] {
            for link in recLinks {
                let href = link.attribute(forName: "href")?.stringValue ?? ""
                let recId = extractBookId(from: href)
                let recTitle = link.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !recId.isEmpty, !recTitle.isEmpty, !seenRecIds.contains(recId) {
                    seenRecIds.insert(recId)
                    let group = (Int(recId) ?? 0) / 1000
                    let recCover = "https://img.wenku8.com/image/\(group)/\(recId)/\(recId)s.jpg"
                    recommendations.append(RecommendedBook(
                        id: recId,
                        title: recTitle,
                        coverURL: recCover,
                        isCompleted: seenRecIds.count > 5
                    ))
                }
            }
        }

        return ParsedBookPage(
            title: title,
            author: author,
            publisher: publisher,
            status: status,
            lastUpdated: lastUpdated,
            wordCount: wordCount,
            popularity: popularity,
            latestChapter: latestChapter,
            tags: tags,
            description: description,
            coverURL: coverURL,
            catalogURL: catalogURL,
            recommendations: recommendations
        )
    }

    public static func parseCatalogPage(html: String, catalogURL: String) throws -> (String, String, [VolumeItem]) {
        let doc = try XMLDocument(xmlString: html, options: [.documentTidyHTML])
        let title = (try? doc.nodes(forXPath: "//div[@id='title']").first?.stringValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawInfo = (try? doc.nodes(forXPath: "//div[@id='info']").first?.stringValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = rawInfo.replacingOccurrences(of: #"^作者[:：]\s*"#, with: "", options: .regularExpression)

        guard let cells = try? doc.nodes(forXPath: "//table[contains(@class,'css')]//td") as? [XMLElement], !cells.isEmpty else {
            throw Wenku8Error.parseError("未能解析小说目录表格")
        }

        var volumes: [VolumeItem] = []
        var currentTitle: String?
        var currentChapters: [ChapterItem] = []
        var volIndex = 0

        func flushVolume() {
            if let vTitle = currentTitle {
                volumes.append(VolumeItem(
                    id: "vol_\(volIndex)",
                    index: volIndex,
                    title: vTitle,
                    chapters: currentChapters
                ))
            }
        }

        for cell in cells {
            let classAttr = cell.attribute(forName: "class")?.stringValue ?? ""
            let classes = classAttr.split(separator: " ").map(String.init)
            if classes.contains("vcss") {
                flushVolume()
                volIndex += 1
                currentTitle = cell.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "第\(volIndex)卷"
                currentChapters = []
            } else if classes.contains("ccss"), currentTitle != nil {
                if let link = (try? cell.nodes(forXPath: ".//a[@href]").first) as? XMLElement,
                   let href = link.attribute(forName: "href")?.stringValue {
                    let chapTitle = (link.stringValue ?? "")
                        .replacingOccurrences(of: "\u{00A0}", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chapTitle.isEmpty {
                        let chapIdx = currentChapters.count
                        let resolvedURL = resolveURL(href, relativeTo: catalogURL)
                        let isIllus = Self.colorKeywords.contains(chapTitle)
                        currentChapters.append(ChapterItem(
                            id: "v\(volIndex)_c\(chapIdx)_\(resolvedURL)",
                            title: chapTitle,
                            url: resolvedURL,
                            volumeIndex: volIndex,
                            chapterIndex: chapIdx,
                            isIllustrationChapter: isIllus
                        ))
                    }
                }
            }
        }
        flushVolume()

        return (title, author, volumes)
    }

    public static func parseChapterContent(html: String, chapter: ChapterItem) throws -> ChapterContent {
        let doc = try XMLDocument(xmlString: html, options: [.documentTidyHTML])
        guard let contentNode = try? doc.nodes(forXPath: "//div[@id='content']").first as? XMLElement else {
            throw Wenku8Error.parseError("章节《\(chapter.title)》正文区域不存在")
        }

        var rawPieces: [String] = []
        var foundImages: [String] = []

        func walk(_ node: XMLNode) {
            switch node.kind {
            case .text:
                if let text = node.stringValue {
                    rawPieces.append(text)
                }
            case .element:
                guard let el = node as? XMLElement else { return }
                let tag = (el.name ?? "").lowercased()
                let idAttr = (el.attribute(forName: "id")?.stringValue ?? "").lowercased()
                if tag == "script" || tag == "style" || idAttr == "contentdp" {
                    return
                }
                if tag == "br" {
                    rawPieces.append("\n")
                    return
                }
                if tag == "img" {
                    let src = (el.attribute(forName: "src")?.stringValue ?? el.attribute(forName: "data-src")?.stringValue ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !src.isEmpty {
                        let resolved = resolveURL(src, relativeTo: chapter.url)
                        foundImages.append(resolved)
                        rawPieces.append("\n@@IMG@@\(resolved)@@IMG@@\n")
                    }
                    return
                }
                let isBlock = ["p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6"].contains(tag)
                for child in el.children ?? [] {
                    walk(child)
                }
                if isBlock {
                    rawPieces.append("\n")
                }
            default:
                break
            }
        }

        walk(contentNode)

        let combined = rawPieces.joined()
        var tokens: [ChapterToken] = []
        for rawLine in combined.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("@@IMG@@") && line.hasSuffix("@@IMG@@") {
                let start = line.index(line.startIndex, offsetBy: 7)
                let end = line.index(line.endIndex, offsetBy: -7)
                let url = String(line[start..<end])
                if !url.isEmpty {
                    tokens.append(.image(url))
                }
            } else {
                tokens.append(.paragraph(line))
            }
        }

        return ChapterContent(chapter: chapter, tokens: tokens, imageURLs: foundImages)
    }

    public static func parseReviewsPage(html: String, baseURL: String) -> [BookReview] {
        guard let doc = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]),
              let rows = try? doc.nodes(forXPath: "//table[contains(@class,'grid')]//tr") as? [XMLElement] else {
            return []
        }

        var reviews: [BookReview] = []
        for (idx, row) in rows.enumerated() {
            guard let cells = try? row.nodes(forXPath: "./td") as? [XMLElement], cells.count >= 4 else { continue }
            let link = (try? cells[0].nodes(forXPath: ".//a[@href]").first) as? XMLElement
            let title = (link?.stringValue ?? cells[0].stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let href = link?.attribute(forName: "href")?.stringValue ?? ""
            let stats = (cells[1].stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let author = (cells[2].stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let time = (cells[3].stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                reviews.append(BookReview(
                    id: "rev_\(idx)_\(href)",
                    title: title,
                    replyStats: stats,
                    author: author,
                    time: time,
                    url: resolveURL(href, relativeTo: baseURL)
                ))
            }
        }
        return reviews
    }

    public static func parseReviewThreadPage(html: String, baseURL: String) -> [ReviewPost] {
        guard let doc = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]),
              let tables = try? doc.nodes(forXPath: "//div[@id='content']//table[contains(@class,'grid')]") as? [XMLElement] else {
            return []
        }

        var posts: [ReviewPost] = []
        let floorRegex = try? NSRegularExpression(pattern: #"(\d+)#"#)
        let replyFloorRegex = try? NSRegularExpression(pattern: #"(?:回复|Re:|@|引用)\s*(\d+)\s*(?:#|楼)"#, options: .caseInsensitive)
        let replyAuthorRegex = try? NSRegularExpression(pattern: #"^(?:回复|@)\s*([^\s:：@]{1,24})"#, options: .caseInsensitive)

        func extractCleanText(from node: XMLNode) -> String {
            switch node.kind {
            case .text:
                return node.stringValue ?? ""
            case .element:
                guard let el = node as? XMLElement else { return "" }
                let tag = (el.name ?? "").lowercased()
                if tag == "script" || tag == "style" || tag == "textarea" || tag == "form" || tag == "input" {
                    return ""
                }
                if tag == "br" {
                    return "\n"
                }
                let inner = (el.children ?? []).map(extractCleanText).joined()
                if tag == "div" || tag == "p" || tag == "blockquote" {
                    return inner + "\n"
                }
                return inner
            default:
                return ""
            }
        }

        for (idx, table) in tables.enumerated() {
            // Skip reply form table (<caption>回复书评：</caption> or textarea/form)
            if let captions = try? table.nodes(forXPath: "./caption") as? [XMLElement], !captions.isEmpty {
                continue
            }
            if let forms = try? table.nodes(forXPath: ".//textarea | .//form") as? [XMLElement], !forms.isEmpty {
                continue
            }

            guard let oddCell = (try? table.nodes(forXPath: ".//td[contains(@class,'odd')]").first) as? XMLElement,
                  let evenCell = (try? table.nodes(forXPath: ".//td[contains(@class,'even')]").first) as? XMLElement else {
                continue
            }

            // Real post tables always have a floor anchor (<a name="yid...">X#</a>) or user link
            let hasFloorAnchor = ((try? evenCell.nodes(forXPath: ".//a[contains(@href,'#yid')]").first) != nil)
            let hasUserLink = ((try? oddCell.nodes(forXPath: ".//a[contains(@href,'userpage.php')]").first) != nil)
            guard hasFloorAnchor || hasUserLink else {
                continue
            }

            let author = ((try? oddCell.nodes(forXPath: ".//strong//a").first?.stringValue)
                ?? (try? oddCell.nodes(forXPath: ".//strong").first?.stringValue) ?? "匿名书友")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let rawAvatar = (try? oddCell.nodes(forXPath: ".//img[contains(@class,'avatar')]/@src").first?.stringValue) ?? ""
            let avatarURL = rawAvatar.isEmpty ? "" : resolveURL(rawAvatar, relativeTo: baseURL)

            let oddLines = (oddCell.stringValue ?? "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != author && !$0.contains("发送消息") && !$0.contains("查看资料") }
            let level = oddLines.first ?? "书友"

            let headerRightText = (try? evenCell.nodes(forXPath: ".//div[contains(@style,'float:right')]").first?.stringValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            var floorNum = posts.count + 1
            if let floorRegex,
               let match = floorRegex.firstMatch(in: headerRightText, range: NSRange(headerRightText.startIndex..., in: headerRightText)),
               let range = Range(match.range(at: 1), in: headerRightText),
               let parsed = Int(headerRightText[range]) {
                floorNum = parsed
            }

            let timeText = headerRightText
                .replacingOccurrences(of: #"\|\s*\d+#.*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let rawBody: String
            if let bodyDiv = (try? evenCell.nodes(forXPath: "./div[last()]").first) as? XMLElement {
                rawBody = extractCleanText(from: bodyDiv)
            } else {
                rawBody = extractCleanText(from: evenCell)
            }

            let bodyText = rawBody
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            guard !bodyText.isEmpty else { continue }

            var replyToFloor: Int?
            if let replyFloorRegex,
               let m = replyFloorRegex.firstMatch(in: bodyText, range: NSRange(bodyText.startIndex..., in: bodyText)),
               let r = Range(m.range(at: 1), in: bodyText),
               let target = Int(bodyText[r]),
               target != floorNum {
                replyToFloor = target
            }

            var replyToAuthor: String?
            if let replyAuthorRegex,
               let m = replyAuthorRegex.firstMatch(in: bodyText, range: NSRange(bodyText.startIndex..., in: bodyText)),
               let r = Range(m.range(at: 1), in: bodyText) {
                replyToAuthor = String(bodyText[r])
            }

            posts.append(ReviewPost(
                id: "post_\(idx)_\(floorNum)",
                floor: floorNum,
                author: author,
                authorLevel: level,
                avatarURL: avatarURL,
                time: timeText,
                content: bodyText,
                replyToFloor: replyToFloor,
                replyToAuthor: replyToAuthor
            ))
        }
        return posts
    }

    public static func parseAuthorBooksPage(html: String) -> [AuthorBookItem] {
        guard let doc = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]),
              let blocks = try? doc.nodes(forXPath: "//div[@id='content']//div[contains(@style,'width:373px')]") as? [XMLElement] else {
            return []
        }

        var items: [AuthorBookItem] = []
        for block in blocks {
            let href = (try? block.nodes(forXPath: ".//a[contains(@href,'/book/')]/@href").first?.stringValue) ?? ""
            let bookId = extractBookId(from: href)
            let title = (try? block.nodes(forXPath: ".//b//a").first?.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cover = (try? block.nodes(forXPath: ".//img/@src").first?.stringValue) ?? ""
            let text = block.stringValue ?? ""
            var author = ""
            var category = ""
            var updatedAt = ""
            var wordCount = ""
            var status = ""
            var tags: [String] = []
            var summary = ""

            for line in text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
                if line.hasPrefix("作者:") {
                    let parts = line.components(separatedBy: "/")
                    author = parts.first?.replacingOccurrences(of: "作者:", with: "") ?? ""
                    if parts.count > 1 { category = parts[1].replacingOccurrences(of: "分类:", with: "") }
                } else if line.hasPrefix("更新:") {
                    let parts = line.components(separatedBy: "/")
                    updatedAt = parts.first?.replacingOccurrences(of: "更新:", with: "") ?? ""
                    if parts.count > 1 { wordCount = parts[1].replacingOccurrences(of: "字数:", with: "") }
                    if parts.count > 2 { status = parts[2] }
                } else if line.hasPrefix("Tags:") {
                    tags = line.replacingOccurrences(of: "Tags:", with: "")
                        .components(separatedBy: .whitespaces)
                        .filter { !$0.isEmpty }
                } else if line.hasPrefix("简介:") {
                    summary = line.replacingOccurrences(of: "简介:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }

            if !bookId.isEmpty && !title.isEmpty {
                let group = (Int(bookId) ?? 0) / 1000
                let resolvedCover = cover.isEmpty
                    ? "https://img.wenku8.com/image/\(group)/\(bookId)/\(bookId)s.jpg"
                    : resolveURL(cover, relativeTo: "https://www.wenku8.cc")
                items.append(AuthorBookItem(
                    id: bookId,
                    title: title,
                    author: author,
                    category: category,
                    updatedAt: updatedAt,
                    wordCount: wordCount,
                    status: status,
                    popularity: "",
                    tags: tags,
                    summary: summary,
                    coverURL: resolvedCover
                ))
            }
        }
        return items
    }

    // MARK: - Helpers

    public static func resolveURL(_ href: String, relativeTo base: String) -> String {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if let baseURL = URL(string: base), let resolved = URL(string: trimmed, relativeTo: baseURL) {
            return resolved.absoluteString
        }
        return trimmed
    }

    private static func looksLikeImageBytes(_ data: Data) -> Bool {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return true }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }
        if data.starts(with: Array("GIF8".utf8)) { return true }
        if data.count >= 12 && data.prefix(4) == Data("RIFF".utf8) && data[8..<12] == Data("WEBP".utf8) {
            return true
        }
        return false
    }

    public static func detectImageFormat(data: Data, urlString: String) -> (String, String) {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return (".jpg", "image/jpeg") }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return (".png", "image/png") }
        if data.starts(with: Array("GIF8".utf8)) { return (".gif", "image/gif") }
        if data.count >= 12 && data.prefix(4) == Data("RIFF".utf8) && data[8..<12] == Data("WEBP".utf8) {
            return (".webp", "image/webp")
        }
        let lower = urlString.lowercased()
        if lower.hasSuffix(".png") { return (".png", "image/png") }
        if lower.hasSuffix(".gif") { return (".gif", "image/gif") }
        if lower.hasSuffix(".webp") { return (".webp", "image/webp") }
        return (".jpg", "image/jpeg")
    }

    public static func measureImageSize(data: Data) -> (Int, Int) {
        if let rep = NSBitmapImageRep(data: data) {
            return (max(1, rep.pixelsWide), max(1, rep.pixelsHigh))
        }
        if let img = NSImage(data: data) {
            return (max(1, Int(img.size.width)), max(1, Int(img.size.height)))
        }
        return (600, 850)
    }
}
