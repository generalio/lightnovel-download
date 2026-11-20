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
    public let title: String
    public let author: String
    public let coverURL: String
    public let publisher: String
    public let status: String
    public let wordCount: String
    public let lastUpdated: String
    public let popularity: String
    public let tags: [String]
    public let summary: String
    public let addedAt: Date

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
        addedAt: Date = Date()
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
