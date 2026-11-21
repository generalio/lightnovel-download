import AppKit
import AVFoundation
import Foundation
import SwiftUI
import WebKit
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

public extension ReaderTheme {
    var backgroundColor: Color {
        switch self {
        case .paper: return Color(nsColor: .textBackgroundColor)
        case .sepia: return Color(red: 0.96, green: 0.93, blue: 0.85)
        case .green: return Color(red: 0.88, green: 0.94, blue: 0.88)
        case .night: return Color(red: 0.11, green: 0.12, blue: 0.14)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .paper: return Color.primary
        case .sepia: return Color(red: 0.24, green: 0.18, blue: 0.12)
        case .green: return Color(red: 0.13, green: 0.22, blue: 0.15)
        case .night: return Color(red: 0.86, green: 0.87, blue: 0.90)
        }
    }

    var swatchColor: Color {
        switch self {
        case .paper: return Color.white
        case .sepia: return Color(red: 0.93, green: 0.86, blue: 0.72)
        case .green: return Color(red: 0.78, green: 0.90, blue: 0.79)
        case .night: return Color(red: 0.18, green: 0.20, blue: 0.24)
        }
    }

    var paperBackingColor: Color {
        switch self {
        case .paper: return Color(red: 0.97, green: 0.97, blue: 0.96)
        case .sepia: return Color(red: 0.94, green: 0.90, blue: 0.81)
        case .green: return Color(red: 0.85, green: 0.91, blue: 0.85)
        case .night: return Color(red: 0.14, green: 0.15, blue: 0.18)
        }
    }
}

public extension ReaderFontFamily {
    func swiftUIFont(customFontName: String = "", size: CGFloat, bold: Bool = false) -> Font {
        switch self {
        case .systemDefault:
            return .system(size: size, weight: bold ? .bold : .regular)
        default:
            let nsFont = ReaderPaginator.resolveNSFont(
                family: self,
                customFontName: customFontName,
                size: size,
                bold: bold
            )
            return Font(nsFont)
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
    var autoRefreshCookieEnabled: Bool?
    var cookieRefreshIntervalMinutes: Int?
    var lastCookieRefreshAt: Date?
    var knownCloudBookIds: [String]?
    var pendingCloudDeleteIds: [String]?
    var lastBookshelfSyncAt: Date?
    var readerTheme: ReaderTheme?
    var readerPageMode: ReaderPageMode?
    var readerScriptMode: ReaderScriptMode?
    var readerFontFamily: ReaderFontFamily?
    var readerCustomFontName: String?
    var readerFontSize: Double?
    var readerLineSpacing: Double?
    var readerParagraphSpacing: Double?
    var readerColumnWidth: Double?
    var readerEdgePadding: Double?
    var readerIndentEnabled: Bool?
    var readerDualPageEnabled: Bool?
    var readerSpeechRate: Float?
    var readerBookmarks: [ReaderBookmarkNote]?
    var lastReadPageRatioByChapter: [String: Double]?
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
    @Published public var readerPageMode: ReaderPageMode = .curl
    @Published public var readerScriptMode: ReaderScriptMode = .original
    @Published public var readerFontFamily: ReaderFontFamily = .systemDefault
    @Published public var readerCustomFontName: String = "PingFang SC"
    @Published public var readerFontSize: Double = 17
    @Published public var readerLineSpacing: Double = 9
    @Published public var readerParagraphSpacing: Double = 12
    @Published public var readerColumnWidth: Double = 760
    @Published public var readerEdgePadding: Double = 24
    @Published public var readerIndentEnabled: Bool = true
    @Published public var readerDualPageEnabled: Bool = false
    @Published public var isFocusReadingMode: Bool = false
    @Published public var readerStartAtEndOnOpen: Bool = false
    @Published public var readerSpeechRate: Float = 0.50
    @Published public var isSpeakingChapter: Bool = false
    @Published public var readerBookmarks: [ReaderBookmarkNote] = []
    @Published public var lastReadChapterByBook: [String: String] = [:]
    @Published public var lastReadPageRatioByChapter: [String: Double] = [:]

    public let availableSystemFontFamilies: [String] = NSFontManager.shared.availableFontFamilies.sorted()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var speechDelegateProxy: SpeechSynthesizerDelegateProxy?

    // Discovery & Search & Tags
    @Published public var searchQuery: String = ""
    @Published public var searchScope: SearchScope = .articleName
    @Published public var discoveryBooks: [AuthorBookItem] = []
    @Published public var discoveryTitle: String = "发现好书"
    @Published public var activeDiscoverySort: String = ""
    @Published public var discoveryPage: Int = 1
    @Published public var discoveryTotalPages: Int = 1
    @Published public var isLoadingDiscovery: Bool = false
    @Published public var discoveryNotice: String?
    @Published public var discoveryRequiresCookie: Bool = false
    @Published public var tagGroups: [TagGroup] = []
    @Published public var isLoadingTags: Bool = false
    @Published public var selectedTag: String?
    @Published public var tagSortOption: TagSortOption = .hot
    @Published public var showTagBrowser: Bool = false
    @Published public var coverImageCache: [String: NSImage] = [:]

    // Assembly
    @Published public var assemblyConfig = AssemblyConfig()

    // Download state
    @Published public var isDownloading: Bool = false
    @Published public var currentStageText: String = "就绪"
    @Published public var progressFraction: Double = 0
    @Published public var logs: [String] = []
    @Published public var outputs: [OutputArtifact] = []

    // Unified Bookshelf & History
    @Published public var bookmarks: [BookmarkEntry] = []
    @Published public var history: [BookmarkEntry] = []
    @Published public var cloudBookcaseGroups: [CloudBookcaseGroup] = []
    @Published public var activeCloudGroupFilter: String = "all"
    @Published public var cloudCapacityTip: String = ""
    @Published public var isSyncingBookshelf: Bool = false
    @Published public var bookshelfSyncNotice: String?
    @Published public var lastBookshelfSyncAt: Date?
    @Published public var isVotingBook: Bool = false

    private var knownCloudBookIds: Set<String> = []
    private var pendingCloudDeleteIds: Set<String> = []

    // Settings & Auth
    @Published public var scrollToAssemblyToken: UUID?
    @Published public var baseURL: String = "https://www.wenku8.cc"
    @Published public var customCookie: String = ""
    @Published public var isTestingCookie: Bool = false
    @Published public var isRefreshingCookie: Bool = false
    @Published public var autoRefreshCookieEnabled: Bool = true
    @Published public var cookieRefreshIntervalMinutes: Int = 15
    @Published public var lastCookieRefreshAt: Date?
    @Published public var nextCookieRefreshAt: Date?
    @Published public var lastCookieRefreshStatus: String?
    @Published public var cookieVerifyMessage: String?
    @Published public var cookieVerifyPassed: Bool?
    @Published public var userProfile: Wenku8UserProfile?
    @Published public var showWebLoginSheet: Bool = false
    @Published public var maxConcurrency: Int = 8
    @Published public var politeDelaySeconds: Double = 0.25
    @Published public var outputDirectoryPath: String

    private enum DiscoverySource {
        case list(title: String, path: String)
        case search(query: String, scope: SearchScope)
        case tag(name: String, sort: TagSortOption)
    }
    private var lastDiscoverySource: DiscoverySource?

    private let client: Wenku8Client
    private let epubBuilder = EPUBBuilder()
    private var activeDownloadTask: Task<Void, Never>?
    private var cookieRefreshTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?
    private var inflightCoverURLs = Set<String>()

    public init() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? (NSHomeDirectory() + "/Downloads")
        self.outputDirectoryPath = downloads
        self.client = Wenku8Client(baseURL: "https://www.wenku8.cc", cookie: "", timeout: 15, politeDelaySeconds: 0.25)
        loadPersistedState()
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppDidBecomeActive()
            }
        }
        Task {
            await syncClientSettings()
            if !customCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await refreshCookieKeepAlive(silent: true)
                if self.cookieVerifyPassed == true {
                    self.syncBookshelfBidirectionally(silent: true)
                }
            }
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

    public func selectFirstVolumeOnly() {
        guard let first = bookDetail?.volumes.first else { return }
        selectedChapterIds = Set(first.chapters.map(\.id))
    }

    public var areAllChaptersSelected: Bool {
        guard let detail = bookDetail else { return false }
        let allIds = detail.volumes.flatMap(\.chapters).map(\.id)
        return !allIds.isEmpty && allIds.allSatisfy { selectedChapterIds.contains($0) }
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

    public func openChapterInReader(_ chapter: ChapterItem, startAtLastPage: Bool = false) {
        stopSpeech()
        selectedSection = .reader
        isLoadingPreview = true
        previewImages = [:]
        errorBanner = nil
        readerStartAtEndOnOpen = startAtLastPage

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

    public func updateChapterProgressRatio(chapterId: String, ratio: Double) {
        lastReadPageRatioByChapter[chapterId] = min(1.0, max(0.0, ratio))
        savePersistedState()
    }

    public func toggleReaderBookmark(
        chapter: ChapterItem,
        pageIndex: Int,
        progressRatio: Double,
        excerpt: String
    ) {
        let bookId = bookDetail?.bookId ?? "unknown"
        if let idx = readerBookmarks.firstIndex(where: { $0.chapterId == chapter.id && $0.pageIndex == pageIndex }) {
            readerBookmarks.remove(at: idx)
            statusBanner = "已移除页内书签"
        } else {
            let note = ReaderBookmarkNote(
                bookId: bookId,
                chapterId: chapter.id,
                chapterTitle: chapter.title,
                pageIndex: pageIndex,
                progressRatio: progressRatio,
                excerpt: excerpt.isEmpty ? chapter.title : excerpt
            )
            readerBookmarks.insert(note, at: 0)
            statusBanner = "已添加书签：\(chapter.title) 第 \(pageIndex + 1) 页"
        }
        savePersistedState()
    }

    public func removeReaderBookmark(id: UUID) {
        readerBookmarks.removeAll { $0.id == id }
        savePersistedState()
    }

    public func isReaderPageBookmarked(chapterId: String, pageIndex: Int) -> Bool {
        readerBookmarks.contains { $0.chapterId == chapterId && $0.pageIndex == pageIndex }
    }

    public func readerBookmarksForCurrentBook() -> [ReaderBookmarkNote] {
        guard let bookId = bookDetail?.bookId else { return readerBookmarks }
        return readerBookmarks.filter { $0.bookId == bookId }
    }

    public func toggleSpeechForCurrentChapter() {
        if isSpeakingChapter {
            stopSpeech()
            return
        }
        guard let content = previewChapter else { return }
        let speechText = ReaderPaginator.plainTextForSpeech(content: content, scriptMode: readerScriptMode)
        guard !speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let proxy = SpeechSynthesizerDelegateProxy { [weak self] in
            Task { @MainActor in
                self?.isSpeakingChapter = false
            }
        }
        speechDelegateProxy = proxy
        speechSynthesizer.delegate = proxy

        let utterance = AVSpeechUtterance(string: speechText)
        let preferredLang = (readerScriptMode == .traditional) ? "zh-TW" : "zh-CN"
        utterance.voice = AVSpeechSynthesisVoice(language: preferredLang) ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, readerSpeechRate))
        speechSynthesizer.speak(utterance)
        isSpeakingChapter = true
    }

    public func stopSpeech() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        isSpeakingChapter = false
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

    // MARK: - Discovery, Search & Tags

    public func loadAuthorWorks(author: String) {
        guard !author.isEmpty else { return }
        searchQuery = author
        searchScope = .author
        selectedSection = .discovery
        performDiscoverySearch(page: 1)
    }

    public func performDiscoverySearch(page: Int = 1) {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoadingDiscovery = true
        discoveryNotice = nil
        discoveryRequiresCookie = false
        activeDiscoverySort = ""
        selectedTag = nil
        discoveryTitle = "搜索「\(q)」"
        lastDiscoverySource = .search(query: q, scope: searchScope)

        Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let res = try await client.searchBooksPaged(query: q, scope: searchScope, page: page, baseURL: baseURL)
                self.discoveryBooks = res.items
                self.discoveryPage = res.currentPage
                self.discoveryTotalPages = res.totalPages
                if res.items.isEmpty {
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

    public func loadDiscoveryList(title: String, path: String, page: Int = 1) {
        isLoadingDiscovery = true
        discoveryNotice = nil
        discoveryRequiresCookie = false
        activeDiscoverySort = path
        selectedTag = nil
        discoveryTitle = title
        lastDiscoverySource = .list(title: title, path: path)

        Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let res = try await client.fetchDiscoveryBooksPaged(listPath: path, page: page, baseURL: baseURL)
                self.discoveryBooks = res.items
                self.discoveryPage = res.currentPage
                self.discoveryTotalPages = res.totalPages
                if res.items.isEmpty {
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

    public func loadTagGroups() {
        guard !isLoadingTags else { return }
        isLoadingTags = true
        Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let groups = try await client.fetchTagGroups(baseURL: baseURL)
                self.tagGroups = groups
            } catch let Wenku8Error.loginRequired(msg) {
                self.discoveryNotice = msg
                self.discoveryRequiresCookie = true
            } catch {
                self.discoveryNotice = "加载标签云失败：\(error.localizedDescription)"
            }
            self.isLoadingTags = false
        }
    }

    public func loadBooksByTag(_ tag: String, sort: TagSortOption? = nil, page: Int = 1) {
        let activeSort = sort ?? tagSortOption
        tagSortOption = activeSort
        selectedTag = tag
        activeDiscoverySort = ""
        isLoadingDiscovery = true
        discoveryNotice = nil
        discoveryRequiresCookie = false
        discoveryTitle = "标签「\(tag)」· \(activeSort.displayName)"
        lastDiscoverySource = .tag(name: tag, sort: activeSort)

        Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let res = try await client.fetchBooksByTag(tag: tag, sort: activeSort, page: page, baseURL: baseURL)
                self.discoveryBooks = res.items
                self.discoveryPage = res.currentPage
                self.discoveryTotalPages = res.totalPages
                if res.items.isEmpty {
                    self.discoveryNotice = "标签「\(tag)」下暂无符合条件的作品。"
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

    public func loadDiscoveryPage(_ targetPage: Int) {
        let clamped = max(1, min(discoveryTotalPages, targetPage))
        guard clamped != discoveryPage, let source = lastDiscoverySource else { return }
        switch source {
        case .list(let title, let path):
            loadDiscoveryList(title: title, path: path, page: clamped)
        case .search(let query, let scope):
            searchQuery = query
            searchScope = scope
            performDiscoverySearch(page: clamped)
        case .tag(let name, let sort):
            loadBooksByTag(name, sort: sort, page: clamped)
        }
    }

    // MARK: - Unified Bookshelf (Cloud + Local Bidirectional Sync) & Account Actions

    public var isCloudSessionAvailable: Bool {
        !customCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cookieVerifyPassed != false
    }

    public func syncBookshelfBidirectionally(silent: Bool = false) {
        guard !isSyncingBookshelf else { return }
        guard !customCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            bookshelfSyncNotice = "未登录账号：当前使用本地书架，登录后将自动与云端双向同步。"
            return
        }

        isSyncingBookshelf = true
        if !silent {
            bookshelfSyncNotice = nil
        }

        Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let firstPull = try await client.fetchAllCloudBookcase(baseURL: baseURL)
                await syncRefreshedCookieFromClient()
                if !firstPull.groups.isEmpty {
                    self.cloudBookcaseGroups = firstPull.groups
                }
                self.cloudCapacityTip = firstPull.capacityTip

                let initialPlan = BookmarkEntry.reconcileWithCloud(
                    local: self.bookmarks,
                    cloud: firstPull.items,
                    previouslyKnownCloudIds: self.knownCloudBookIds,
                    pendingCloudDeleteIds: self.pendingCloudDeleteIds
                )

                // 1. Flush offline local deletions to cloud
                for recordId in initialPlan.cloudRecordIdsToDelete {
                    try? await client.removeFromCloudBookcase(recordId: recordId, baseURL: baseURL)
                }
                self.pendingCloudDeleteIds.removeAll()

                // 2. Push unsynced local additions up to cloud
                var pushedCount = 0
                for bookId in initialPlan.bookIdsToPushToCloud {
                    if (try? await client.addToCloudBookcase(bookId: bookId, baseURL: baseURL)) != nil {
                        pushedCount += 1
                    }
                }

                // 3. Re-pull if we pushed items up so cloudRecordId/groupId are populated
                let finalPage: CloudBookcasePage
                if pushedCount > 0 {
                    finalPage = (try? await client.fetchAllCloudBookcase(baseURL: baseURL)) ?? firstPull
                    if !finalPage.groups.isEmpty {
                        self.cloudBookcaseGroups = finalPage.groups
                    }
                    self.cloudCapacityTip = finalPage.capacityTip
                } else {
                    finalPage = firstPull
                }

                let finalPlan = BookmarkEntry.reconcileWithCloud(
                    local: initialPlan.mergedBookmarks,
                    cloud: finalPage.items,
                    previouslyKnownCloudIds: self.knownCloudBookIds.union(initialPlan.bookIdsToPushToCloud),
                    pendingCloudDeleteIds: self.pendingCloudDeleteIds
                )

                self.bookmarks = finalPlan.mergedBookmarks
                self.knownCloudBookIds = finalPlan.knownCloudBookIds
                self.lastBookshelfSyncAt = Date()
                self.cookieVerifyPassed = true
                let syncMsg = "云端与本地书架已双向同步（共 \(self.bookmarks.count) 本）"
                self.bookshelfSyncNotice = syncMsg
                if !silent {
                    self.statusBanner = syncMsg
                }
                self.appendLog("书架双向同步完成：共 \(self.bookmarks.count) 本，上传 \(pushedCount) 本，清理远端删除 \(initialPlan.cloudRecordIdsToDelete.count) 本")
                self.savePersistedState()
            } catch Wenku8Error.loginRequired {
                self.cookieVerifyPassed = false
                self.bookshelfSyncNotice = "登录已过期，当前显示本地缓存书架；重新登录后将自动双向同步。"
                if !silent {
                    self.errorBanner = "登录已过期，请重新网页登录后同步云端书架。"
                }
            } catch {
                self.bookshelfSyncNotice = "云端同步失败（暂显示本地书架）：\(error.localizedDescription)"
                if !silent {
                    self.errorBanner = error.localizedDescription
                }
            }
            self.isSyncingBookshelf = false
        }
    }

    public func moveBookmarkToCloudGroup(_ entry: BookmarkEntry, toClassId: String) {
        guard !entry.cloudRecordId.isEmpty, entry.cloudGroupId != toClassId else { return }
        Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                try await client.moveCloudBookcaseItems(
                    recordIds: [entry.cloudRecordId],
                    fromClassId: entry.cloudGroupId.isEmpty ? "0" : entry.cloudGroupId,
                    toClassId: toClassId,
                    baseURL: baseURL
                )
                if let idx = self.bookmarks.firstIndex(where: { $0.id == entry.id }) {
                    self.bookmarks[idx].cloudGroupId = toClassId
                    self.savePersistedState()
                }
                self.statusBanner = "已将《\(entry.title)》移动到目标书架分组"
            } catch {
                self.errorBanner = error.localizedDescription
            }
        }
    }

    public func openBookmarkChapter(_ entry: BookmarkEntry) {
        guard !entry.cloudChapterId.isEmpty else {
            loadBook(inputOverride: entry.id)
            return
        }
        bookInput = entry.id
        errorBanner = nil
        statusBanner = nil
        isLoadingBook = true
        Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let detail = try await client.fetchBookDetail(rawInput: entry.id)
                self.bookDetail = detail
                self.recordHistory(detail: detail)
                if let match = detail.volumes.flatMap(\.chapters).first(where: { $0.url.contains("/\(entry.cloudChapterId).htm") }) {
                    self.openChapterInReader(match)
                } else {
                    self.selectedSection = .catalog
                }
            } catch {
                self.errorBanner = error.localizedDescription
            }
            self.isLoadingBook = false
        }
    }

    public func voteCurrentBook() {
        guard let detail = bookDetail, !isVotingBook else { return }
        isVotingBook = true
        errorBanner = nil
        statusBanner = nil

        Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let msg = try await client.voteBook(bookId: detail.bookId, baseURL: detail.baseURL)
                await syncRefreshedCookieFromClient()
                self.statusBanner = "《\(detail.title)》：\(msg)"
                self.appendLog("推荐投票《\(detail.title)》：\(msg)")
            } catch {
                self.errorBanner = error.localizedDescription
            }
            self.isVotingBook = false
        }
    }

    // MARK: - Bookmarks & History

    public func isBookmarked(_ bookId: String) -> Bool {
        bookmarks.contains { $0.id == bookId }
    }

    public func toggleBookmark(_ detail: BookDetail) {
        let entry = BookmarkEntry(
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
        )
        toggleBookmarkFromEntry(entry)
    }

    public func toggleBookmarkFromAuthorItem(_ item: AuthorBookItem) {
        let entry = BookmarkEntry(
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
        )
        toggleBookmarkFromEntry(entry)
    }

    public func toggleBookmarkFromEntry(_ entry: BookmarkEntry) {
        if isBookmarked(entry.id) {
            removeBookmark(id: entry.id)
        } else {
            addBookmarkUnified(entry)
        }
    }

    private func addBookmarkUnified(_ entry: BookmarkEntry) {
        pendingCloudDeleteIds.remove(entry.id)
        if !bookmarks.contains(where: { $0.id == entry.id }) {
            bookmarks.insert(entry, at: 0)
        }
        savePersistedState()

        guard isCloudSessionAvailable else {
            statusBanner = "未登录账号，已暂存到本地书架（登录后自动同步至云端）"
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let msg = try await client.addToCloudBookcase(bookId: entry.id, baseURL: baseURL)
                await syncRefreshedCookieFromClient()
                if let idx = self.bookmarks.firstIndex(where: { $0.id == entry.id }) {
                    self.bookmarks[idx].hasSyncedToCloud = true
                }
                self.knownCloudBookIds.insert(entry.id)
                self.savePersistedState()
                self.statusBanner = "《\(entry.title)》：\(msg)"
                self.syncBookshelfBidirectionally(silent: true)
            } catch Wenku8Error.loginRequired {
                self.cookieVerifyPassed = false
                self.statusBanner = "登录已失效，已暂存本地书架（重新登录后自动推送云端）"
            } catch {
                self.bookshelfSyncNotice = "已先存本地，推至云端失败：\(error.localizedDescription)"
            }
        }
    }

    public func removeBookmark(id: String) {
        let existing = bookmarks.first(where: { $0.id == id })
        bookmarks.removeAll { $0.id == id }

        let wasSynced = (existing?.hasSyncedToCloud == true) || knownCloudBookIds.contains(id)
        let recordId = existing?.cloudRecordId ?? ""

        if !isCloudSessionAvailable {
            if wasSynced {
                pendingCloudDeleteIds.insert(id)
            }
            savePersistedState()
            return
        }

        if wasSynced && recordId.isEmpty {
            pendingCloudDeleteIds.insert(id)
        }
        savePersistedState()

        if !recordId.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                await syncClientSettings()
                do {
                    try await client.removeFromCloudBookcase(recordId: recordId, baseURL: baseURL)
                    await syncRefreshedCookieFromClient()
                    self.knownCloudBookIds.remove(id)
                    self.pendingCloudDeleteIds.remove(id)
                    self.savePersistedState()
                } catch Wenku8Error.loginRequired {
                    self.cookieVerifyPassed = false
                    self.pendingCloudDeleteIds.insert(id)
                    self.savePersistedState()
                } catch {
                    self.pendingCloudDeleteIds.insert(id)
                    self.savePersistedState()
                }
            }
        } else if wasSynced {
            // Pull & delete via sync if recordId wasn't cached yet
            syncBookshelfBidirectionally(silent: true)
        }
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
            await self.syncRefreshedCookieFromClient()
            self.cookieVerifyPassed = res.isLoggedIn
            self.cookieVerifyMessage = res.message
            if res.isLoggedIn {
                self.userProfile = try? await self.client.fetchUserProfile(baseURL: self.baseURL)
                await self.syncRefreshedCookieFromClient()
                self.lastCookieRefreshAt = Date()
                self.lastCookieRefreshStatus = "验证成功并已同步最新会话"
                self.rescheduleCookieRefresh()
                self.syncBookshelfBidirectionally(silent: true)
            } else {
                self.userProfile = nil
                self.stopCookieRefreshScheduler()
            }
            self.isTestingCookie = false
        }
    }

    public func applyWebLoginCookie(_ rawCookie: String) {
        customCookie = Wenku8Client.normalizeCookie(rawCookie)
        showWebLoginSheet = false
        discoveryRequiresCookie = false
        discoveryNotice = nil
        bookshelfSyncNotice = nil
        testCookieValidity()
    }

    public func clearSavedCookie() {
        customCookie = ""
        cookieVerifyMessage = nil
        cookieVerifyPassed = nil
        userProfile = nil
        lastCookieRefreshStatus = nil
        stopCookieRefreshScheduler()
        Task { await syncClientSettings() }
    }

    public func rescheduleCookieRefresh() {
        cookieRefreshTask?.cancel()
        cookieRefreshTask = nil

        let trimmed = customCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard autoRefreshCookieEnabled, !trimmed.isEmpty, cookieVerifyPassed != false else {
            nextCookieRefreshAt = nil
            savePersistedState()
            return
        }

        let minutes = max(1, min(180, cookieRefreshIntervalMinutes))
        cookieRefreshIntervalMinutes = minutes
        let nextDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        nextCookieRefreshAt = nextDate
        savePersistedState()

        cookieRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
                } catch {
                    break
                }
                guard let self, !Task.isCancelled else { break }
                await self.refreshCookieKeepAlive(silent: true)
            }
        }
    }

    public func stopCookieRefreshScheduler() {
        cookieRefreshTask?.cancel()
        cookieRefreshTask = nil
        nextCookieRefreshAt = nil
        savePersistedState()
    }

    private func handleAppDidBecomeActive() {
        guard autoRefreshCookieEnabled,
              !customCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              cookieVerifyPassed != false else {
            return
        }
        let minGap = TimeInterval(max(300, (cookieRefreshIntervalMinutes * 60) / 2))
        if let last = lastCookieRefreshAt, Date().timeIntervalSince(last) < minGap {
            return
        }
        Task { [weak self] in
            await self?.refreshCookieKeepAlive(silent: true)
        }
    }

    public func refreshCookieKeepAlive(silent: Bool = false) async {
        let trimmed = customCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRefreshingCookie else { return }
        isRefreshingCookie = true
        defer { isRefreshingCookie = false }

        // Merge any newer wenku8 cookies persisted in WebKit's WKHTTPCookieStore
        let webCookies = await fetchWenku8CookiesFromWebStore()
        if !webCookies.isEmpty {
            let mergedFromWeb = Wenku8Client.mergeCookieHeader(existing: customCookie, setCookies: webCookies)
            if !mergedFromWeb.isEmpty && mergedFromWeb != customCookie {
                customCookie = mergedFromWeb
            }
        }

        await syncClientSettings()
        let result = await client.refreshCookieSession(baseURL: baseURL)

        if result.isLoggedIn {
            if !result.updatedCookie.isEmpty && result.updatedCookie != customCookie {
                customCookie = result.updatedCookie
            }
            if let profile = result.profile {
                userProfile = profile
            }
            cookieVerifyPassed = true
            lastCookieRefreshAt = Date()
            lastCookieRefreshStatus = result.message
            if !silent {
                cookieVerifyMessage = result.message
                statusBanner = result.message
            }
            appendLog("Cookie 保活刷新：\(result.message)")
            rescheduleCookieRefresh()
        } else {
            cookieVerifyPassed = false
            lastCookieRefreshStatus = result.message
            if !silent {
                cookieVerifyMessage = result.message
                errorBanner = result.message
            }
            appendLog("Cookie 保活检测失败：\(result.message)")
            stopCookieRefreshScheduler()
        }
    }

    private func syncRefreshedCookieFromClient() async {
        let latest = await client.currentCookieSnapshot()
        if !latest.isEmpty && latest != customCookie {
            customCookie = latest
            savePersistedState()
        }
    }

    private func fetchWenku8CookiesFromWebStore() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let relevant = cookies.filter { $0.domain.lowercased().contains("wenku8") }
                continuation.resume(returning: relevant)
            }
        }
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

    public func downloadFullBookAsSingleEPUB() {
        guard let detail = bookDetail else {
            errorBanner = "请先拉取书籍目录"
            return
        }
        guard !isDownloading else { return }
        selectAllChapters()
        let allVolumes = detail.volumes.compactMap { vol in
            vol.chapters.isEmpty ? nil : (vol, vol.chapters)
        }
        startDownload(detail: detail, chosenVolumes: allVolumes, forceMergedSingle: true)
    }

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

        startDownload(detail: detail, chosenVolumes: chosenVolumes, forceMergedSingle: false)
    }

    private func startDownload(
        detail: BookDetail,
        chosenVolumes: [(VolumeItem, [ChapterItem])],
        forceMergedSingle: Bool
    ) {
        errorBanner = nil
        statusBanner = nil
        isDownloading = true
        progressFraction = 0
        currentStageText = forceMergedSingle ? "准备整本打包单本 EPUB..." : "准备下载..."
        selectedSection = .tasks
        savePersistedState()

        var configSnapshot = assemblyConfig
        if forceMergedSingle {
            configSnapshot.exportMode = .mergedSingle
        }
        let outURL = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
        let concurrencySnapshot = maxConcurrency
        let chapterConcurrency = max(1, min(4, concurrencySnapshot))

        activeDownloadTask = Task { [weak self] in
            guard let self else { return }
            await syncClientSettings()
            do {
                let flatTargets: [(volIdx: Int, chapIdx: Int, volTitle: String, chapter: ChapterItem)] = chosenVolumes.enumerated().flatMap { vOffset, pair in
                    pair.1.enumerated().map { cOffset, chap in
                        (vOffset, cOffset, pair.0.title, chap)
                    }
                }
                let totalChapters = flatTargets.count
                var fetchedByKey: [String: ChapterContent] = [:]
                var completedChapters = 0

                try await withThrowingTaskGroup(of: (String, String, String, ChapterContent).self) { group in
                    var nextIndex = 0
                    for _ in 0..<min(chapterConcurrency, totalChapters) {
                        let target = flatTargets[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            try Task.checkCancellation()
                            let content = try await self.client.fetchChapterContent(chapter: target.chapter, baseURL: detail.baseURL)
                            return (target.chapter.id, target.volTitle, target.chapter.title, content)
                        }
                    }

                    while let (chapId, volTitle, chapTitle, content) = try await group.next() {
                        try Task.checkCancellation()
                        fetchedByKey[chapId] = content
                        completedChapters += 1
                        currentStageText = "拉取文本 (\(completedChapters)/\(totalChapters))：\(volTitle) · \(chapTitle)"
                        appendLog("已抓取 (\(completedChapters)/\(totalChapters))：[\(volTitle)] \(chapTitle)")
                        progressFraction = 0.55 * (Double(completedChapters) / Double(max(1, totalChapters)))

                        if nextIndex < totalChapters {
                            let nextTarget = flatTargets[nextIndex]
                            nextIndex += 1
                            group.addTask {
                                try Task.checkCancellation()
                                let content = try await self.client.fetchChapterContent(chapter: nextTarget.chapter, baseURL: detail.baseURL)
                                return (nextTarget.chapter.id, nextTarget.volTitle, nextTarget.chapter.title, content)
                            }
                        }
                    }
                }

                var builtVolumes: [VolumeBuildInput] = []
                var allImageURLs: [String] = []
                if !detail.coverURL.isEmpty {
                    allImageURLs.append(detail.coverURL)
                }

                for (vol, chaps) in chosenVolumes {
                    var bodyContents: [ChapterContent] = []
                    var illusContent: ChapterContent?
                    for chap in chaps {
                        if let content = fetchedByKey[chap.id] {
                            allImageURLs.append(contentsOf: content.imageURLs)
                            if chap.isIllustrationChapter && illusContent == nil {
                                illusContent = content
                            } else {
                                bodyContents.append(content)
                            }
                        }
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
            lastReadChapterByBook: lastReadChapterByBook,
            autoRefreshCookieEnabled: autoRefreshCookieEnabled,
            cookieRefreshIntervalMinutes: cookieRefreshIntervalMinutes,
            lastCookieRefreshAt: lastCookieRefreshAt,
            knownCloudBookIds: Array(knownCloudBookIds),
            pendingCloudDeleteIds: Array(pendingCloudDeleteIds),
            lastBookshelfSyncAt: lastBookshelfSyncAt,
            readerTheme: readerTheme,
            readerPageMode: readerPageMode,
            readerScriptMode: readerScriptMode,
            readerFontFamily: readerFontFamily,
            readerCustomFontName: readerCustomFontName,
            readerFontSize: readerFontSize,
            readerLineSpacing: readerLineSpacing,
            readerParagraphSpacing: readerParagraphSpacing,
            readerColumnWidth: readerColumnWidth,
            readerEdgePadding: readerEdgePadding,
            readerIndentEnabled: readerIndentEnabled,
            readerDualPageEnabled: readerDualPageEnabled,
            readerSpeechRate: readerSpeechRate,
            readerBookmarks: readerBookmarks,
            lastReadPageRatioByChapter: lastReadPageRatioByChapter
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
        autoRefreshCookieEnabled = state.autoRefreshCookieEnabled ?? true
        cookieRefreshIntervalMinutes = max(1, min(180, state.cookieRefreshIntervalMinutes ?? 15))
        lastCookieRefreshAt = state.lastCookieRefreshAt
        knownCloudBookIds = Set(state.knownCloudBookIds ?? [])
        pendingCloudDeleteIds = Set(state.pendingCloudDeleteIds ?? [])
        lastBookshelfSyncAt = state.lastBookshelfSyncAt
        if let t = state.readerTheme { readerTheme = t }
        if let pm = state.readerPageMode { readerPageMode = pm }
        if let sm = state.readerScriptMode { readerScriptMode = sm }
        if let ff = state.readerFontFamily { readerFontFamily = ff }
        if let cf = state.readerCustomFontName, !cf.isEmpty { readerCustomFontName = cf }
        if let fs = state.readerFontSize { readerFontSize = fs }
        if let ls = state.readerLineSpacing { readerLineSpacing = ls }
        if let ps = state.readerParagraphSpacing { readerParagraphSpacing = ps }
        if let cw = state.readerColumnWidth { readerColumnWidth = cw }
        if let ep = state.readerEdgePadding { readerEdgePadding = max(8, min(96, ep)) }
        if let ie = state.readerIndentEnabled { readerIndentEnabled = ie }
        if let dp = state.readerDualPageEnabled { readerDualPageEnabled = dp }
        if let sr = state.readerSpeechRate { readerSpeechRate = sr }
        if let rbm = state.readerBookmarks { readerBookmarks = rbm }
        if let ratios = state.lastReadPageRatioByChapter { lastReadPageRatioByChapter = ratios }
    }
}

private final class SpeechSynthesizerDelegateProxy: NSObject, AVSpeechSynthesizerDelegate {
    let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}
