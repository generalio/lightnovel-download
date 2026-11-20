import AppKit
import Foundation
import SwiftUI
import Wenku8Core

public enum SidebarSection: String, CaseIterable, Identifiable {
    case discovery = "发现"
    case bookshelf = "书架与历史"
    case catalog = "目录与选章"
    case reader = "在线阅读"
    case tasks = "任务与产物"
    case settings = "设置"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .discovery: return "sparkles"
        case .bookshelf: return "books.vertical.fill"
        case .catalog: return "list.bullet.rectangle.portrait.fill"
        case .reader: return "book.pages.fill"
        case .tasks: return "arrow.down.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

public enum ReaderTheme: String, CaseIterable, Identifiable {
    case paper = "素白"
    case sepia = "羊皮纸"
    case green = "护眼绿"
    case night = "夜间"

    public var id: String { rawValue }

    public var backgroundColor: Color {
        switch self {
        case .paper: return Color(nsColor: .textBackgroundColor)
        case .sepia: return Color(red: 0.96, green: 0.93, blue: 0.85)
        case .green: return Color(red: 0.88, green: 0.94, blue: 0.88)
        case .night: return Color(red: 0.11, green: 0.12, blue: 0.14)
        }
    }

    public var foregroundColor: Color {
        switch self {
        case .paper: return Color.primary
        case .sepia: return Color(red: 0.24, green: 0.18, blue: 0.12)
        case .green: return Color(red: 0.13, green: 0.22, blue: 0.15)
        case .night: return Color(red: 0.86, green: 0.87, blue: 0.90)
        }
    }

    public var swatchColor: Color {
        switch self {
        case .paper: return Color.white
        case .sepia: return Color(red: 0.93, green: 0.86, blue: 0.72)
        case .green: return Color(red: 0.78, green: 0.90, blue: 0.79)
        case .night: return Color(red: 0.18, green: 0.20, blue: 0.24)
        }
    }
}

public enum ReaderFontFamily: String, CaseIterable, Identifiable, Codable {
    case pingfang = "PingFang SC"
    case kaiti = "Kaiti SC"
    case songti = "Songti SC"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pingfang: return "黑体"
        case .kaiti: return "楷体"
        case .songti: return "宋体"
        }
    }
}

private struct PersistedAppState: Codable {
    var bookmarks: [BookmarkEntry]
    var history: [BookmarkEntry]
    var outputs: [OutputArtifact]
    var assemblyConfig: AssemblyConfig
    var baseURL: String
    var maxConcurrency: Int
    var politeDelaySeconds: Double
    var outputDirectoryPath: String
    var customCookie: String
    var lastReadChapterByBook: [String: String]?
}

@MainActor
public final class StudioViewModel: ObservableObject {
    @Published public var selectedSection: SidebarSection = .catalog
    @Published public var bookInput: String = "3115"
    @Published public var chapterSearchQuery: String = ""
    @Published public var volumeRangeInput: String = ""

    @Published public var bookDetail: BookDetail?
    @Published public var coverPreviewImage: NSImage?
    @Published public var isLoadingBook: Bool = false
    @Published public var errorBanner: String?
    @Published public var statusBanner: String?

    @Published public var selectedChapterIds: Set<String> = []
    @Published public var expandedVolumeIds: Set<String> = []

    // Reviews Inspector (inside Catalog)
    @Published public var showReviewsInspector: Bool = false
    @Published public var reviews: [BookReview] = []
    @Published public var isLoadingReviews: Bool = false
    @Published public var selectedReview: BookReview?
    @Published public var reviewPosts: [ReviewPost] = []
    @Published public var isLoadingReviewPosts: Bool = false

    // Reader
    @Published public var previewChapter: ChapterContent?
    @Published public var previewImages: [String: NSImage] = [:]
    @Published public var isLoadingPreview: Bool = false
    @Published public var readerTheme: ReaderTheme = .sepia
    @Published public var readerFontSize: Double = 17
    @Published public var readerLineSpacing: Double = 9
    @Published public var readerParagraphSpacing: Double = 12
    @Published public var readerColumnWidth: Double = 760
    @Published public var readerFontFamily: ReaderFontFamily = .pingfang
    @Published public var readerIndentEnabled: Bool = true
    @Published public var lastReadChapterByBook: [String: String] = [:]

    // Discovery & Search
    @Published public var searchQuery: String = ""
    @Published public var searchScope: SearchScope = .articleName
    @Published public var discoveryBooks: [AuthorBookItem] = []
    @Published public var discoveryTitle: String = "发现好书"
    @Published public var activeDiscoverySort: String = ""
    @Published public var isLoadingDiscovery: Bool = false
    @Published public var discoveryNotice: String?
    @Published public var discoveryRequiresCookie: Bool = false
    @Published public var coverImageCache: [String: NSImage] = [:]

    // Assembly
    @Published public var assemblyConfig = AssemblyConfig()

    // Download state
    @Published public var isDownloading: Bool = false
    @Published public var currentStageText: String = "就绪"
    @Published public var progressFraction: Double = 0
    @Published public var logs: [String] = []
    @Published public var outputs: [OutputArtifact] = []

    // Bookmarks & History
    @Published public var bookmarks: [BookmarkEntry] = []
    @Published public var history: [BookmarkEntry] = []

    // Settings & Auth
    @Published public var scrollToAssemblyToken: UUID?
    @Published public var baseURL: String = "https://www.wenku8.cc"
    @Published public var customCookie: String = ""
    @Published public var isTestingCookie: Bool = false
    @Published public var cookieVerifyMessage: String?
    @Published public var cookieVerifyPassed: Bool?
    @Published public var showWebLoginSheet: Bool = false
    @Published public var maxConcurrency: Int = 8
    @Published public var politeDelaySeconds: Double = 0.25
    @Published public var outputDirectoryPath: String

    private let client: Wenku8Client
    private let epubBuilder = EPUBBuilder()
    private var activeDownloadTask: Task<Void, Never>?
    private var inflightCoverURLs = Set<String>()

    public init() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? (NSHomeDirectory() + "/Downloads")
        self.outputDirectoryPath = downloads
        self.client = Wenku8Client(baseURL: "https://www.wenku8.cc", cookie: "", timeout: 15, politeDelaySeconds: 0.25)
        loadPersistedState()
        Task {
            await syncClientSettings()
        }
    }

    public func syncClientSettings() async {
        await client.updateSettings(
            baseURL: baseURL,
            cookie: customCookie,
            timeout: 15,
            politeDelaySeconds: politeDelaySeconds
        )
        savePersistedState()
    }

    public func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let stamped = "[\(formatter.string(from: Date()))] \(line)"
        logs.append(stamped)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    // MARK: - Cover Thumbnail Cache

    public func ensureCoverLoaded(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, coverImageCache[trimmed] == nil, !inflightCoverURLs.contains(trimmed) else { return }
        inflightCoverURLs.insert(trimmed)

        Task { [weak self] in
            guard let self else { return }
            defer { self.inflightCoverURLs.remove(trimmed) }
            if let asset = try? await client.downloadSingleImage(urlString: trimmed, referer: baseURL),
               let img = NSImage(data: asset.data) {
                self.coverImageCache[trimmed] = img
            }
        }
    }

    // MARK: - Book Loading & Selection

    public func loadBook(inputOverride: String? = nil) {
        let query = (inputOverride ?? bookInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            errorBanner = "请输入书号或书籍网址"
            return
        }
        bookInput = query
        errorBanner = nil
        statusBanner = nil
        isLoadingBook = true
        selectedReview = nil
        reviewPosts = []
        reviews = []
        appendLog("开始拉取书籍详情：\(query)")

        Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let detail = try await client.fetchBookDetail(rawInput: query) { [weak self] msg in
                    Task { @MainActor in
                        self?.appendLog(msg)
                    }
                }
                self.bookDetail = detail
                self.selectedSection = .catalog
                self.expandedVolumeIds = Set(detail.volumes.prefix(2).map(\.id))
                if let firstVol = detail.volumes.first {
                    self.selectedChapterIds = Set(firstVol.chapters.map(\.id))
                } else {
                    self.selectedChapterIds = []
                }
                self.recordHistory(detail: detail)
                self.appendLog("拉取成功：《\(detail.title)》（\(detail.author)），共 \(detail.volumes.count) 卷")

                // Load cover asynchronously (with fallback to Vol 1 illustration image)
                self.coverPreviewImage = nil
                var loadedCover: NSImage?
                if !detail.coverURL.isEmpty {
                    do {
                        let coverAsset = try await client.downloadSingleImage(urlString: detail.coverURL, referer: detail.baseURL)
                        loadedCover = NSImage(data: coverAsset.data)
                    } catch {
                        self.appendLog("主页封面加载失败（\(detail.coverURL)）：\(error.localizedDescription)")
                    }
                }
                if loadedCover == nil,
                   let firstIllusChap = detail.volumes.first?.chapters.first(where: { $0.isIllustrationChapter }) {
                    if let illusContent = try? await client.fetchChapterContent(chapter: firstIllusChap, baseURL: detail.baseURL),
                       let firstImgURL = illusContent.imageURLs.first,
                       let illusAsset = try? await client.downloadSingleImage(urlString: firstImgURL, referer: detail.baseURL) {
                        loadedCover = NSImage(data: illusAsset.data)
                    }
                }
                self.coverPreviewImage = loadedCover
                if let loadedCover, !detail.coverURL.isEmpty {
                    self.coverImageCache[detail.coverURL] = loadedCover
                }
            } catch {
                self.errorBanner = error.localizedDescription
                self.appendLog("拉取失败：\(error.localizedDescription)")
            }
            self.isLoadingBook = false
        }
    }

    public var selectedVolumesCount: Int {
        guard let detail = bookDetail else { return 0 }
        return detail.volumes.filter { vol in
            vol.chapters.contains { selectedChapterIds.contains($0.id) }
        }.count
    }

    public var selectedBodyChaptersCount: Int {
        guard let detail = bookDetail else { return 0 }
        return detail.volumes.flatMap(\.chapters).filter { !$0.isIllustrationChapter && selectedChapterIds.contains($0.id) }.count
    }

    public func volumeSelectionState(_ vol: VolumeItem) -> Int {
        let ids = Set(vol.chapters.map(\.id))
        let count = ids.intersection(selectedChapterIds).count
        if count == 0 { return 0 }
        if count == ids.count { return 2 }
        return 1
    }

    public func toggleVolume(_ vol: VolumeItem) {
        let ids = Set(vol.chapters.map(\.id))
        if volumeSelectionState(vol) == 2 {
            selectedChapterIds.subtract(ids)
        } else {
            selectedChapterIds.formUnion(ids)
        }
    }

    public func toggleChapter(_ chapter: ChapterItem) {
        if selectedChapterIds.contains(chapter.id) {
            selectedChapterIds.remove(chapter.id)
        } else {
            selectedChapterIds.insert(chapter.id)
        }
    }

    public func selectAllChapters() {
        guard let detail = bookDetail else { return }
        selectedChapterIds = Set(detail.volumes.flatMap(\.chapters).map(\.id))
    }

    public func clearSelection() {
        selectedChapterIds.removeAll()
    }

    public func invertSelection() {
        guard let detail = bookDetail else { return }
        let all = Set(detail.volumes.flatMap(\.chapters).map(\.id))
        selectedChapterIds = all.subtracting(selectedChapterIds)
    }

    public func selectIllustratedVolumesOnly() {
        guard let detail = bookDetail else { return }
        let ids = detail.volumes.filter(\.hasIllustrationChapter).flatMap(\.chapters).map(\.id)
        selectedChapterIds = Set(ids)
    }

    public func applyVolumeRangeSelection() {
        guard let detail = bookDetail else { return }
        let spec = volumeRangeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spec.isEmpty else { return }
        var targetIndices = Set<Int>()
        for part in spec.replacingOccurrences(of: "，", with: ",").split(separator: ",") {
            let token = part.trimmingCharacters(in: .whitespaces)
            if token.contains("-") {
                let bounds = token.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
                if bounds.count == 2, let s = Int(bounds[0]), let e = Int(bounds[1]), s <= e {
                    for i in s...e { targetIndices.insert(i) }
                }
            } else if let single = Int(token) {
                targetIndices.insert(single)
            }
        }
        let ids = detail.volumes.filter { targetIndices.contains($0.index) }.flatMap(\.chapters).map(\.id)
        selectedChapterIds = Set(ids)
    }

    // MARK: - Built-in Reader

    public func openChapterInReader(_ chapter: ChapterItem) {
        selectedSection = .reader
        isLoadingPreview = true
        previewImages = [:]
        errorBanner = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await client.fetchChapterContent(chapter: chapter, baseURL: bookDetail?.baseURL)
                self.previewChapter = content
                if let bookId = self.bookDetail?.bookId {
                    self.lastReadChapterByBook[bookId] = chapter.id
                    self.savePersistedState()
                }
                if !content.imageURLs.isEmpty {
                    let downloaded = try await client.downloadImages(
                        urls: content.imageURLs,
                        referer: bookDetail?.baseURL,
                        maxConcurrency: maxConcurrency
                    )
                    var imgs: [String: NSImage] = [:]
                    for (url, asset) in downloaded {
                        if let nsImg = NSImage(data: asset.data) {
                            imgs[url] = nsImg
                        }
                    }
                    self.previewImages = imgs
                }
            } catch {
                self.errorBanner = error.localizedDescription
            }
            self.isLoadingPreview = false
        }
    }

    public func readerProgressInfo() -> (current: Int, total: Int)? {
        guard let detail = bookDetail, let current = previewChapter?.chapter else { return nil }
        let flat = detail.volumes.flatMap(\.chapters)
        guard let idx = flat.firstIndex(where: { $0.id == current.id }) else { return nil }
        return (idx + 1, flat.count)
    }

    public func openLastReadOrFirstChapter() {
        guard let detail = bookDetail else { return }
        let flat = detail.volumes.flatMap(\.chapters)
        if let savedId = lastReadChapterByBook[detail.bookId],
           let found = flat.first(where: { $0.id == savedId }) {
            openChapterInReader(found)
        } else if let first = flat.first(where: { !$0.isIllustrationChapter }) ?? flat.first {
            openChapterInReader(first)
        }
    }

    public func adjacentChapter(offset: Int) -> ChapterItem? {
        guard let detail = bookDetail, let current = previewChapter?.chapter else { return nil }
        let flat = detail.volumes.flatMap(\.chapters)
        guard let idx = flat.firstIndex(where: { $0.id == current.id }) else { return nil }
        let target = idx + offset
        guard target >= 0 && target < flat.count else { return nil }
        return flat[target]
    }

    // MARK: - Reviews Inspector (in Catalog)

    public func openReviewsInspectorForCurrentBook() {
        guard let detail = bookDetail else { return }
        showReviewsInspector = true
        if !reviews.isEmpty { return }
        isLoadingReviews = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let list = try await client.fetchReviews(bookId: detail.bookId, baseURL: detail.baseURL)
                self.reviews = list
            } catch {
                self.errorBanner = "拉取书评失败：\(error.localizedDescription)"
            }
            self.isLoadingReviews = false
        }
    }

    public func openReviewThread(_ review: BookReview) {
        selectedReview = review
        reviewPosts = []
        isLoadingReviewPosts = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let posts = try await client.fetchReviewThread(
                    reviewURL: review.url,
                    baseURL: bookDetail?.baseURL ?? baseURL
                )
                self.reviewPosts = posts
            } catch {
                self.errorBanner = "拉取楼层详情失败：\(error.localizedDescription)"
            }
            self.isLoadingReviewPosts = false
        }
    }

    // MARK: - Discovery & Search

    public func loadAuthorWorks(author: String) {
        guard !author.isEmpty else { return }
        searchQuery = author
        searchScope = .author
        selectedSection = .discovery
        performDiscoverySearch()
    }

    public func performDiscoverySearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoadingDiscovery = true
        discoveryNotice = nil
        discoveryRequiresCookie = false
        activeDiscoverySort = ""
        discoveryTitle = "搜索「\(q)」"

        Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let items = try await client.searchBooks(query: q, scope: searchScope, baseURL: baseURL)
                self.discoveryBooks = items
                if items.isEmpty {
                    self.discoveryNotice = "未找到与「\(q)」相关的作品。"
                }
            } catch let Wenku8Error.loginRequired(msg) {
                self.discoveryNotice = msg
                self.discoveryRequiresCookie = true
            } catch {
                self.discoveryNotice = error.localizedDescription
            }
            self.isLoadingDiscovery = false
        }
    }

    public func loadDiscoveryList(title: String, path: String) {
        isLoadingDiscovery = true
        discoveryNotice = nil
        discoveryRequiresCookie = false
        activeDiscoverySort = path
        discoveryTitle = title

        Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let items = try await client.fetchDiscoveryBooks(listPath: path, baseURL: baseURL)
                self.discoveryBooks = items
                if items.isEmpty {
                    self.discoveryNotice = "当前分类暂无更多数据。"
                }
            } catch let Wenku8Error.loginRequired(msg) {
                self.discoveryNotice = msg
                self.discoveryRequiresCookie = true
            } catch {
                self.discoveryNotice = error.localizedDescription
            }
            self.isLoadingDiscovery = false
        }
    }

    // MARK: - Bookmarks & History

    public func isBookmarked(_ bookId: String) -> Bool {
        bookmarks.contains { $0.id == bookId }
    }

    public func toggleBookmark(_ detail: BookDetail) {
        if let idx = bookmarks.firstIndex(where: { $0.id == detail.bookId }) {
            bookmarks.remove(at: idx)
        } else {
            bookmarks.insert(BookmarkEntry(
                id: detail.bookId,
                title: detail.title,
                author: detail.author,
                coverURL: detail.coverURL,
                publisher: detail.publisher,
                status: detail.status,
                wordCount: detail.wordCount,
                lastUpdated: detail.lastUpdated,
                popularity: detail.popularity,
                tags: detail.tags,
                summary: detail.description
            ), at: 0)
        }
        savePersistedState()
    }

    public func toggleBookmarkFromAuthorItem(_ item: AuthorBookItem) {
        if let idx = bookmarks.firstIndex(where: { $0.id == item.id }) {
            bookmarks.remove(at: idx)
        } else {
            bookmarks.insert(BookmarkEntry(
                id: item.id,
                title: item.title,
                author: item.author,
                coverURL: item.coverURL,
                publisher: item.category,
                status: item.status,
                wordCount: item.wordCount,
                lastUpdated: item.updatedAt,
                popularity: item.popularity,
                tags: item.tags,
                summary: item.summary
            ), at: 0)
        }
        savePersistedState()
    }

    public func toggleBookmarkFromEntry(_ entry: BookmarkEntry) {
        if let idx = bookmarks.firstIndex(where: { $0.id == entry.id }) {
            bookmarks.remove(at: idx)
        } else {
            bookmarks.insert(entry, at: 0)
        }
        savePersistedState()
    }

    public func removeBookmark(id: String) {
        bookmarks.removeAll { $0.id == id }
        savePersistedState()
    }

    public func removeHistoryItem(id: String) {
        history.removeAll { $0.id == id }
        savePersistedState()
    }

    public func clearHistory() {
        history.removeAll()
        savePersistedState()
    }

    public var cookieDiagnostic: Wenku8Client.CookieDiagnostic {
        Wenku8Client.diagnoseCookieFormat(customCookie)
    }

    public func testCookieValidity() {
        let norm = Wenku8Client.normalizeCookie(customCookie)
        customCookie = norm
        savePersistedState()
        isTestingCookie = true
        cookieVerifyMessage = nil
        cookieVerifyPassed = nil

        Task { [weak self] in
            guard let self else { return }
            await self.syncClientSettings()
            let res = await self.client.verifyCookieLive(cookie: norm, baseURL: self.baseURL)
            self.cookieVerifyPassed = res.isLoggedIn
            self.cookieVerifyMessage = res.message
            self.isTestingCookie = false
        }
    }

    public func applyWebLoginCookie(_ rawCookie: String) {
        customCookie = Wenku8Client.normalizeCookie(rawCookie)
        showWebLoginSheet = false
        discoveryRequiresCookie = false
        discoveryNotice = nil
        testCookieValidity()
    }

    private func recordHistory(detail: BookDetail) {
        history.removeAll { $0.id == detail.bookId }
        history.insert(BookmarkEntry(
            id: detail.bookId,
            title: detail.title,
            author: detail.author,
            coverURL: detail.coverURL,
            publisher: detail.publisher,
            status: detail.status,
            wordCount: detail.wordCount,
            lastUpdated: detail.lastUpdated,
            popularity: detail.popularity,
            tags: detail.tags,
            summary: detail.description
        ), at: 0)
        if history.count > 40 {
            history = Array(history.prefix(40))
        }
        savePersistedState()
    }

    // MARK: - Download & EPUB Assembly

    public func startDownloadSelected() {
        guard let detail = bookDetail else {
            errorBanner = "请先拉取书籍目录"
            return
        }
        guard !isDownloading else { return }

        let chosenVolumes: [(VolumeItem, [ChapterItem])] = detail.volumes.compactMap { vol in
            let chosenChaps = vol.chapters.filter { selectedChapterIds.contains($0.id) }
            return chosenChaps.isEmpty ? nil : (vol, chosenChaps)
        }
        guard !chosenVolumes.isEmpty else {
            errorBanner = "请至少勾选一个章节或分卷"
            return
        }

        errorBanner = nil
        statusBanner = nil
        isDownloading = true
        progressFraction = 0
        currentStageText = "准备下载..."
        selectedSection = .tasks
        savePersistedState()

        let configSnapshot = assemblyConfig
        let outURL = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
        let concurrencySnapshot = maxConcurrency

        activeDownloadTask = Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let totalChapters = chosenVolumes.reduce(0) { $0 + $1.1.count }
                var fetchedChaptersCount = 0
                var builtVolumes: [VolumeBuildInput] = []
                var allImageURLs: [String] = []
                if !detail.coverURL.isEmpty {
                    allImageURLs.append(detail.coverURL)
                }

                for (vol, chaps) in chosenVolumes {
                    try Task.checkCancellation()
                    var bodyContents: [ChapterContent] = []
                    var illusContent: ChapterContent?

                    for chap in chaps {
                        try Task.checkCancellation()
                        currentStageText = "拉取文本：\(vol.title) · \(chap.title)"
                        appendLog("正在抓取：[\(vol.title)] \(chap.title)")
                        let content = try await client.fetchChapterContent(chapter: chap, baseURL: detail.baseURL)
                        allImageURLs.append(contentsOf: content.imageURLs)
                        if chap.isIllustrationChapter && illusContent == nil {
                            illusContent = content
                        } else {
                            bodyContents.append(content)
                        }
                        fetchedChaptersCount += 1
                        progressFraction = 0.55 * (Double(fetchedChaptersCount) / Double(max(1, totalChapters)))
                    }

                    builtVolumes.append(VolumeBuildInput(
                        volume: vol,
                        chapters: bodyContents,
                        illustrationChapter: illusContent
                    ))
                }

                try Task.checkCancellation()
                let uniqueImgCount = Set(allImageURLs).count
                currentStageText = "并发下载图片（共 \(uniqueImgCount) 张）..."
                appendLog("开始并发下载 \(uniqueImgCount) 张图片（并发数 \(concurrencySnapshot)）")

                let downloadedImages = try await client.downloadImages(
                    urls: allImageURLs,
                    referer: detail.baseURL,
                    maxConcurrency: concurrencySnapshot
                ) { [weak self] done, total in
                    Task { @MainActor in
                        guard let self else { return }
                        self.currentStageText = "下载插图：\(done)/\(total)"
                        self.progressFraction = 0.55 + 0.35 * (Double(done) / Double(max(1, total)))
                    }
                }

                try Task.checkCancellation()
                currentStageText = "正在拼装 EPUB..."
                progressFraction = 0.92

                var generated: [OutputArtifact] = []
                if configSnapshot.exportMode == .mergedSingle || builtVolumes.count == 1 {
                    let artifact = try epubBuilder.buildEPUB(
                        book: detail,
                        volumes: builtVolumes,
                        images: downloadedImages,
                        outputDirectory: outURL,
                        config: configSnapshot
                    )
                    generated.append(artifact)
                    appendLog("生成成功：\(artifact.filePath)")
                } else {
                    for (idx, vInput) in builtVolumes.enumerated() {
                        try Task.checkCancellation()
                        currentStageText = "正在打包分卷（\(idx + 1)/\(builtVolumes.count)）：\(vInput.volume.title)"
                        let artifact = try epubBuilder.buildEPUB(
                            book: detail,
                            volumes: [vInput],
                            images: downloadedImages,
                            outputDirectory: outURL,
                            config: configSnapshot
                        )
                        generated.append(artifact)
                        appendLog("生成成功：\(artifact.filePath)")
                    }
                }

                outputs.insert(contentsOf: generated.reversed(), at: 0)
                if outputs.count > 50 {
                    outputs = Array(outputs.prefix(50))
                }
                savePersistedState()
                progressFraction = 1.0
                currentStageText = "已完成（共生成 \(generated.count) 本 EPUB）"
                statusBanner = "已生成 \(generated.count) 本 EPUB 到 \(outputDirectoryPath)"
            } catch is CancellationError {
                currentStageText = "已取消"
                appendLog("下载任务已取消")
            } catch {
                currentStageText = "失败：\(error.localizedDescription)"
                errorBanner = error.localizedDescription
                appendLog("错误：\(error.localizedDescription)")
            }
            isDownloading = false
        }
    }

    public func cancelDownload() {
        activeDownloadTask?.cancel()
        currentStageText = "正在取消..."
    }

    public func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    public func openFileWithDefaultReader(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    public func openOutputFolder() {
        let url = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    public func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: outputDirectoryPath)
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectoryPath = url.path
            savePersistedState()
        }
    }

    public func chooseCustomCoverImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg, .png, .webP, .gif]
        if panel.runModal() == .OK, let url = panel.url {
            assemblyConfig.customCoverPath = url.path
            assemblyConfig.coverSource = .customLocalFile
            savePersistedState()
        }
    }

    public func addExtraColorImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.jpeg, .png, .webP, .gif]
        if panel.runModal() == .OK {
            for url in panel.urls where !assemblyConfig.extraColorImagePaths.contains(url.path) {
                assemblyConfig.extraColorImagePaths.append(url.path)
            }
            savePersistedState()
        }
    }

    // MARK: - Persistence

    private var stateFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("Wenku8Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    public func savePersistedState() {
        let state = PersistedAppState(
            bookmarks: bookmarks,
            history: history,
            outputs: outputs,
            assemblyConfig: assemblyConfig,
            baseURL: baseURL,
            maxConcurrency: maxConcurrency,
            politeDelaySeconds: politeDelaySeconds,
            outputDirectoryPath: outputDirectoryPath,
            customCookie: customCookie,
            lastReadChapterByBook: lastReadChapterByBook
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateFileURL)
        }
    }

    private func loadPersistedState() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(PersistedAppState.self, from: data) else {
            return
        }
        bookmarks = state.bookmarks
        history = state.history
        outputs = state.outputs
        assemblyConfig = state.assemblyConfig
        if !state.baseURL.isEmpty { baseURL = state.baseURL }
        maxConcurrency = max(1, min(16, state.maxConcurrency))
        politeDelaySeconds = state.politeDelaySeconds
        if !state.outputDirectoryPath.isEmpty { outputDirectoryPath = state.outputDirectoryPath }
        customCookie = state.customCookie
        lastReadChapterByBook = state.lastReadChapterByBook ?? [:]
    }
}
