import Foundation

public struct RecommendedBook: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let coverURL: String
    public let isCompleted: Bool

    public init(id: String, title: String, coverURL: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.isCompleted = isCompleted
    }
}

public struct BookReview: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let replyStats: String
    public let author: String
    public let time: String
    public let url: String

    public init(id: String, title: String, replyStats: String, author: String, time: String, url: String) {
        self.id = id
        self.title = title
        self.replyStats = replyStats
        self.author = author
        self.time = time
        self.url = url
    }
}

public struct ReviewPost: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let floor: Int
    public let author: String
    public let authorLevel: String
    public let avatarURL: String
    public let time: String
    public let content: String
    public let replyToFloor: Int?
    public let replyToAuthor: String?

    public init(
        id: String,
        floor: Int,
        author: String,
        authorLevel: String,
        avatarURL: String,
        time: String,
        content: String,
        replyToFloor: Int? = nil,
        replyToAuthor: String? = nil
    ) {
        self.id = id
        self.floor = floor
        self.author = author
        self.authorLevel = authorLevel
        self.avatarURL = avatarURL
        self.time = time
        self.content = content
        self.replyToFloor = replyToFloor
        self.replyToAuthor = replyToAuthor
    }
}

public enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case articleName = "按书名"
    case author = "按作者"
    case bookId = "按书号"

    public var id: String { rawValue }
}

public struct AuthorBookItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    public let category: String
    public let updatedAt: String
    public let wordCount: String
    public let status: String
    public let popularity: String
    public let tags: [String]
    public let summary: String
    public let coverURL: String

    public init(
        id: String,
        title: String,
        author: String,
        category: String,
        updatedAt: String,
        wordCount: String,
        status: String,
        popularity: String = "",
        tags: [String],
        summary: String,
        coverURL: String
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.category = category
        self.updatedAt = updatedAt
        self.wordCount = wordCount
        self.status = status
        self.popularity = popularity
        self.tags = tags
        self.summary = summary
        self.coverURL = coverURL
    }
}

public struct ChapterItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let url: String
    public let volumeIndex: Int
    public let chapterIndex: Int
    public let isIllustrationChapter: Bool

    public init(
        id: String,
        title: String,
        url: String,
        volumeIndex: Int,
        chapterIndex: Int,
        isIllustrationChapter: Bool
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.volumeIndex = volumeIndex
        self.chapterIndex = chapterIndex
        self.isIllustrationChapter = isIllustrationChapter
    }
}

public struct VolumeItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let index: Int
    public let title: String
    public let chapters: [ChapterItem]

    public var hasIllustrationChapter: Bool {
        chapters.contains { $0.isIllustrationChapter }
    }

    public init(id: String, index: Int, title: String, chapters: [ChapterItem]) {
        self.id = id
        self.index = index
        self.title = title
        self.chapters = chapters
    }
}

public struct BookDetail: Codable, Hashable, Sendable {
    public let bookId: String
    public let baseURL: String
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
    public let volumes: [VolumeItem]
    public let recommendations: [RecommendedBook]

    public init(
        bookId: String,
        baseURL: String,
        title: String,
        author: String,
        publisher: String,
        status: String,
        lastUpdated: String,
        wordCount: String,
        popularity: String,
        latestChapter: String,
        tags: [String],
        description: String,
        coverURL: String,
        catalogURL: String,
        volumes: [VolumeItem],
        recommendations: [RecommendedBook]
    ) {
        self.bookId = bookId
        self.baseURL = baseURL
        self.title = title
        self.author = author
        self.publisher = publisher
        self.status = status
        self.lastUpdated = lastUpdated
        self.wordCount = wordCount
        self.popularity = popularity
        self.latestChapter = latestChapter
        self.tags = tags
        self.description = description
        self.coverURL = coverURL
        self.catalogURL = catalogURL
        self.volumes = volumes
        self.recommendations = recommendations
    }
}

public enum ChapterToken: Hashable, Sendable {
    case paragraph(String)
    case image(String)
}

public struct ChapterContent: Sendable {
    public let chapter: ChapterItem
    public let tokens: [ChapterToken]
    public let imageURLs: [String]

    public init(chapter: ChapterItem, tokens: [ChapterToken], imageURLs: [String]) {
        self.chapter = chapter
        self.tokens = tokens
        self.imageURLs = imageURLs
    }
}

public struct DownloadedImageAsset: Sendable {
    public let url: String
    public let data: Data
    public let fileExtension: String
    public let mimeType: String
    public let width: Int
    public let height: Int

    public init(url: String, data: Data, fileExtension: String, mimeType: String, width: Int, height: Int) {
        self.url = url
        self.data = data
        self.fileExtension = fileExtension
        self.mimeType = mimeType
        self.width = width
        self.height = height
    }
}

public enum EPUBVersion: String, CaseIterable, Codable, Identifiable, Sendable {
    case epub3 = "EPUB 3.0 (兼容 2.0)"
    case epub2 = "EPUB 2.0 (经典)"

    public var id: String { rawValue }
}

public enum ExportMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case perVolume = "每卷独立 EPUB"
    case mergedSingle = "多卷合并为单本合集"

    public var id: String { rawValue }
}

public enum CoverSourceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case autoColorFirst = "优先本卷插图首图（无则用封面）"
    case mainPageCover = "强制使用书籍主页封面"
    case customLocalFile = "使用自定义本地图片"

    public var id: String { rawValue }
}

public enum ColorLayoutMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case oneImagePerPage = "每张彩插独立分页"
    case singleScrollPage = "单页连续拼装"
    case skipColor = "忽略彩插页"

    public var id: String { rawValue }
}

public enum ColorPlacement: String, CaseIterable, Codable, Identifiable, Sendable {
    case beforeBody = "置于正文前"
    case afterBody = "置于正文后"

    public var id: String { rawValue }
}

public struct AssemblyConfig: Codable, Hashable, Sendable {
    public var epubVersion: EPUBVersion = .epub3
    public var exportMode: ExportMode = .perVolume
    public var includeCover: Bool = true
    public var includeInfoPage: Bool = true
    public var coverSource: CoverSourceMode = .autoColorFirst
    public var customCoverPath: String = ""
    public var extraColorImagePaths: [String] = []
    public var colorLayout: ColorLayoutMode = .oneImagePerPage
    public var colorPlacement: ColorPlacement = .beforeBody
    public var dedupColorImages: Bool = true
    public var cleanCreditsHeader: Bool = false
    public var textIndentEm: Double = 2.0
    public var lineHeight: Double = 1.65
    public var paragraphSpacingEm: Double = 0.5
    public var filenameTemplate: String = "{title}-{volume}"
    public var customTitleOverride: String = ""
    public var customAuthorOverride: String = ""

    public init() {}
}

public struct BookmarkEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var author: String
    public var coverURL: String
    public var publisher: String
    public var status: String
    public var wordCount: String
    public var lastUpdated: String
    public var popularity: String
    public var tags: [String]
    public var summary: String
    public let addedAt: Date
    public var cloudRecordId: String
    public var cloudGroupId: String
    public var cloudChapterId: String
    public var cloudChapterTitle: String
    public var hasSyncedToCloud: Bool

    public init(
        id: String,
        title: String,
        author: String,
        coverURL: String,
        publisher: String,
        status: String,
        wordCount: String = "",
        lastUpdated: String = "",
        popularity: String = "",
        tags: [String] = [],
        summary: String = "",
        addedAt: Date = Date(),
        cloudRecordId: String = "",
        cloudGroupId: String = "0",
        cloudChapterId: String = "",
        cloudChapterTitle: String = "",
        hasSyncedToCloud: Bool = false
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.publisher = publisher
        self.status = status
        self.wordCount = wordCount
        self.lastUpdated = lastUpdated
        self.popularity = popularity
        self.tags = tags
        self.summary = summary
        self.addedAt = addedAt
        self.cloudRecordId = cloudRecordId
        self.cloudGroupId = cloudGroupId
        self.cloudChapterId = cloudChapterId
        self.cloudChapterTitle = cloudChapterTitle
        self.hasSyncedToCloud = hasSyncedToCloud
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        author = try c.decode(String.self, forKey: .author)
        coverURL = try c.decode(String.self, forKey: .coverURL)
        publisher = try c.decode(String.self, forKey: .publisher)
        status = try c.decode(String.self, forKey: .status)
        wordCount = try c.decodeIfPresent(String.self, forKey: .wordCount) ?? ""
        lastUpdated = try c.decodeIfPresent(String.self, forKey: .lastUpdated) ?? ""
        popularity = try c.decodeIfPresent(String.self, forKey: .popularity) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        cloudRecordId = try c.decodeIfPresent(String.self, forKey: .cloudRecordId) ?? ""
        cloudGroupId = try c.decodeIfPresent(String.self, forKey: .cloudGroupId) ?? "0"
        cloudChapterId = try c.decodeIfPresent(String.self, forKey: .cloudChapterId) ?? ""
        cloudChapterTitle = try c.decodeIfPresent(String.self, forKey: .cloudChapterTitle) ?? ""
        hasSyncedToCloud = try c.decodeIfPresent(Bool.self, forKey: .hasSyncedToCloud) ?? false
    }
}

public struct OutputArtifact: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let filePath: String
    public let fileSizeBytes: Int64
    public let createdAt: Date

    public init(id: UUID = UUID(), title: String, filePath: String, fileSizeBytes: Int64, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.filePath = filePath
        self.fileSizeBytes = fileSizeBytes
        self.createdAt = createdAt
    }
}

public struct PagedBookResult: Hashable, Sendable {
    public let items: [AuthorBookItem]
    public let currentPage: Int
    public let totalPages: Int

    public init(items: [AuthorBookItem], currentPage: Int = 1, totalPages: Int = 1) {
        self.items = items
        self.currentPage = max(1, currentPage)
        self.totalPages = max(1, totalPages)
    }
}

public struct TagGroup: Identifiable, Codable, Hashable, Sendable {
    public var id: String { title }
    public let title: String
    public let tags: [String]

    public init(title: String, tags: [String]) {
        self.title = title
        self.tags = tags
    }
}

public enum TagSortOption: String, CaseIterable, Identifiable, Sendable {
    case updated = "0"
    case hot = "1"
    case completed = "2"
    case anime = "3"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .updated: return "按更新"
        case .hot: return "按热门"
        case .completed: return "只看已完结"
        case .anime: return "只看动画化"
        }
    }
}

public struct CloudBookcaseGroup: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct CloudBookcaseItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(aid)_\(bid)" }
    public let aid: String
    public let bid: String
    public let groupId: String
    public let title: String
    public let author: String
    public let lastReadChapterId: String
    public let lastReadChapterTitle: String
    public let coverURL: String

    public init(
        aid: String,
        bid: String,
        groupId: String = "0",
        title: String,
        author: String,
        lastReadChapterId: String = "",
        lastReadChapterTitle: String = "",
        coverURL: String
    ) {
        self.aid = aid
        self.bid = bid
        self.groupId = groupId
        self.title = title
        self.author = author
        self.lastReadChapterId = lastReadChapterId
        self.lastReadChapterTitle = lastReadChapterTitle
        self.coverURL = coverURL
    }
}

public struct CloudBookcasePage: Codable, Hashable, Sendable {
    public let groups: [CloudBookcaseGroup]
    public let items: [CloudBookcaseItem]
    public let capacityTip: String
    public let activeClassId: String

    public init(
        groups: [CloudBookcaseGroup],
        items: [CloudBookcaseItem],
        capacityTip: String,
        activeClassId: String
    ) {
        self.groups = groups
        self.items = items
        self.capacityTip = capacityTip
        self.activeClassId = activeClassId
    }
}

public struct Wenku8UserProfile: Codable, Hashable, Sendable {
    public let userId: String
    public let username: String
    public let nickname: String
    public let level: String
    public let title: String
    public let holdingPoints: String
    public let experienceValue: String
    public let dailyVoteQuota: String
    public let bookcaseCapacity: String

    public init(
        userId: String = "",
        username: String = "",
        nickname: String = "",
        level: String = "",
        title: String = "",
        holdingPoints: String = "",
        experienceValue: String = "",
        dailyVoteQuota: String = "",
        bookcaseCapacity: String = ""
    ) {
        self.userId = userId
        self.username = username
        self.nickname = nickname
        self.level = level
        self.title = title
        self.holdingPoints = holdingPoints
        self.experienceValue = experienceValue
        self.dailyVoteQuota = dailyVoteQuota
        self.bookcaseCapacity = bookcaseCapacity
    }
}

public struct BookshelfReconcileResult: Sendable {
    public let mergedBookmarks: [BookmarkEntry]
    public let bookIdsToPushToCloud: [String]
    public let cloudRecordIdsToDelete: [String]
    public let knownCloudBookIds: Set<String>

    public init(
        mergedBookmarks: [BookmarkEntry],
        bookIdsToPushToCloud: [String],
        cloudRecordIdsToDelete: [String],
        knownCloudBookIds: Set<String>
    ) {
        self.mergedBookmarks = mergedBookmarks
        self.bookIdsToPushToCloud = bookIdsToPushToCloud
        self.cloudRecordIdsToDelete = cloudRecordIdsToDelete
        self.knownCloudBookIds = knownCloudBookIds
    }
}

public extension BookmarkEntry {
    /// Computes bidirectional bookshelf reconciliation between local entries and fetched cloud items.
    static func reconcileWithCloud(
        local: [BookmarkEntry],
        cloud: [CloudBookcaseItem],
        previouslyKnownCloudIds: Set<String>,
        pendingCloudDeleteIds: Set<String>
    ) -> BookshelfReconcileResult {
        var cloudByAid: [String: CloudBookcaseItem] = [:]
        for item in cloud where cloudByAid[item.aid] == nil {
            cloudByAid[item.aid] = item
        }

        // 1. Offline local deletes that still exist in cloud -> delete from cloud
        var recordIdsToDelete: [String] = []
        for aid in pendingCloudDeleteIds {
            if let cloudItem = cloudByAid[aid], !cloudItem.bid.isEmpty {
                recordIdsToDelete.append(cloudItem.bid)
                cloudByAid.removeValue(forKey: aid)
            }
        }

        // 2. Local books: push unsynced ones to cloud; drop previously-synced ones deleted on cloud
        var merged: [BookmarkEntry] = []
        var pushIds: [String] = []
        var handledAids = Set<String>()

        for var entry in local {
            guard handledAids.insert(entry.id).inserted else { continue }
            if pendingCloudDeleteIds.contains(entry.id) {
                continue
            }

            if let cloudItem = cloudByAid[entry.id] {
                if entry.title.isEmpty { entry.title = cloudItem.title }
                if entry.author.isEmpty { entry.author = cloudItem.author }
                if entry.coverURL.isEmpty { entry.coverURL = cloudItem.coverURL }
                entry.cloudRecordId = cloudItem.bid
                entry.cloudGroupId = cloudItem.groupId
                entry.cloudChapterId = cloudItem.lastReadChapterId
                entry.cloudChapterTitle = cloudItem.lastReadChapterTitle
                entry.hasSyncedToCloud = true
                merged.append(entry)
            } else {
                let wasPreviouslySynced = entry.hasSyncedToCloud || previouslyKnownCloudIds.contains(entry.id)
                if wasPreviouslySynced {
                    // Deleted remotely on wenku8 -> remove locally
                    continue
                } else {
                    // Added locally while offline -> keep locally and push up to cloud
                    pushIds.append(entry.id)
                    merged.append(entry)
                }
            }
        }

        // 3. New books on cloud -> pull down into unified bookshelf
        for item in cloud {
            guard !pendingCloudDeleteIds.contains(item.aid),
                  let _ = cloudByAid[item.aid],
                  !handledAids.contains(item.aid) else { continue }
            handledAids.insert(item.aid)
            merged.append(BookmarkEntry(
                id: item.aid,
                title: item.title,
                author: item.author,
                coverURL: item.coverURL,
                publisher: "",
                status: "",
                cloudRecordId: item.bid,
                cloudGroupId: item.groupId,
                cloudChapterId: item.lastReadChapterId,
                cloudChapterTitle: item.lastReadChapterTitle,
                hasSyncedToCloud: true
            ))
        }

        return BookshelfReconcileResult(
            mergedBookmarks: merged,
            bookIdsToPushToCloud: pushIds,
            cloudRecordIdsToDelete: recordIdsToDelete,
            knownCloudBookIds: Set(cloudByAid.keys)
        )
    }
}

public enum ReaderTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case paper = "素白"
    case sepia = "羊皮纸"
    case green = "护眼绿"
    case night = "夜间"

    public var id: String { rawValue }
}

public enum ReaderFontFamily: String, CaseIterable, Codable, Identifiable, Sendable {
    case systemDefault = "System Default"
    case pingfang = "PingFang SC"
    case songti = "Songti SC"
    case kaiti = "Kaiti SC"
    case yuanti = "Yuanti SC"
    case custom = "Custom System Font"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .systemDefault: return "系统默认"
        case .pingfang: return "黑体"
        case .songti: return "宋体"
        case .kaiti: return "楷体"
        case .yuanti: return "圆体"
        case .custom: return "自定义"
        }
    }
}

public enum ReaderPageMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case curl = "仿真翻页"
    case slide = "平移翻页"
    case scroll = "上下滚动"

    public var id: String { rawValue }
}

public enum ReaderScriptMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case original = "原文"
    case simplified = "简体"
    case traditional = "繁体"

    public var id: String { rawValue }
}

public struct ReaderBookmarkNote: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let bookId: String
    public let chapterId: String
    public let chapterTitle: String
    public let pageIndex: Int
    public let progressRatio: Double
    public let excerpt: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        bookId: String,
        chapterId: String,
        chapterTitle: String,
        pageIndex: Int,
        progressRatio: Double,
        excerpt: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.chapterId = chapterId
        self.chapterTitle = chapterTitle
        self.pageIndex = pageIndex
        self.progressRatio = progressRatio
        self.excerpt = excerpt
        self.createdAt = createdAt
    }
}
