import SwiftUI
import Wenku8Core

struct BookCardItem: Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let coverURL: String
    let publisher: String
    let status: String
    let wordCount: String
    let lastUpdated: String
    let tags: [String]
    let summary: String
    let cloudChapterTitle: String
    let hasSyncedToCloud: Bool
    let cloudRecordId: String
    let cloudGroupId: String

    init(entry: BookmarkEntry, liveDetail: BookDetail? = nil) {
        self.id = entry.id
        self.title = entry.title
        self.author = entry.author
        self.coverURL = entry.coverURL
        self.publisher = entry.publisher.isEmpty ? (liveDetail?.publisher ?? "") : entry.publisher
        self.status = entry.status.isEmpty ? (liveDetail?.status ?? "") : entry.status
        self.wordCount = entry.wordCount.isEmpty ? (liveDetail?.wordCount ?? "") : entry.wordCount
        self.lastUpdated = entry.lastUpdated.isEmpty ? (liveDetail?.lastUpdated ?? "") : entry.lastUpdated
        self.tags = entry.tags.isEmpty ? (liveDetail?.tags ?? []) : entry.tags
        self.summary = entry.summary.isEmpty ? (liveDetail?.description ?? "") : entry.summary
        self.cloudChapterTitle = entry.cloudChapterTitle
        self.hasSyncedToCloud = entry.hasSyncedToCloud
        self.cloudRecordId = entry.cloudRecordId
        self.cloudGroupId = entry.cloudGroupId
    }

    init(authorItem: AuthorBookItem) {
        self.id = authorItem.id
        self.title = authorItem.title
        self.author = authorItem.author
        self.coverURL = authorItem.coverURL
        self.publisher = authorItem.category
        self.status = authorItem.status
        self.wordCount = authorItem.wordCount
        self.lastUpdated = authorItem.updatedAt
        self.tags = authorItem.tags
        self.summary = authorItem.summary
        self.cloudChapterTitle = ""
        self.hasSyncedToCloud = false
        self.cloudRecordId = ""
        self.cloudGroupId = "0"
    }
}

struct BookItemCard: View {
    @EnvironmentObject var vm: StudioViewModel

    let item: BookCardItem
    var showBookmarkButton: Bool = true
    var showSyncBadge: Bool = false
    var deleteTooltip: String? = nil
    var onDelete: (() -> Void)? = nil
    var onToggleBookmark: (() -> Void)? = nil
    var onResumeChapter: (() -> Void)? = nil
    var cloudGroups: [CloudBookcaseGroup] = []
    var onMoveCloudGroup: ((String) -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            coverView

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    HStack(spacing: 6) {
                        if showBookmarkButton, let onToggleBookmark {
                            Button(action: onToggleBookmark) {
                                Image(systemName: vm.isBookmarked(item.id) ? "bookmark.fill" : "bookmark")
                                    .font(.caption)
                                    .foregroundStyle(vm.isBookmarked(item.id) ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .help(vm.isBookmarked(item.id) ? "移出书架" : "加入书架")
                        }

                        if cloudGroups.count > 1, !item.cloudRecordId.isEmpty, let onMoveCloudGroup {
                            Menu {
                                ForEach(cloudGroups.filter { $0.id != item.cloudGroupId }) { group in
                                    Button("移至 \(group.title)") {
                                        onMoveCloudGroup(group.id)
                                    }
                                }
                            } label: {
                                Image(systemName: "folder")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 24)
                            .help("移动到其他云端书架分组")
                        }

                        if let onDelete {
                            Button(role: .destructive, action: onDelete) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .help(deleteTooltip ?? "删除")
                        }
                    }
                }

                HStack(spacing: 6) {
                    if !item.author.isEmpty {
                        Button(item.author) {
                            vm.loadAuthorWorks(author: item.author)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    if !item.publisher.isEmpty {
                        pill(item.publisher, color: .blue)
                    }
                    if !item.status.isEmpty {
                        pill(item.status, color: item.status.contains("完结") ? .green : .orange)
                    }
                }

                if !item.wordCount.isEmpty || !item.lastUpdated.isEmpty {
                    HStack(spacing: 10) {
                        if !item.wordCount.isEmpty {
                            Label(item.wordCount, systemImage: "character.book.closed")
                        }
                        if !item.lastUpdated.isEmpty {
                            Label("更新 \(item.lastUpdated)", systemImage: "calendar")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                if !item.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(item.tags.prefix(5), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }

                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !item.cloudChapterTitle.isEmpty, let onResumeChapter {
                    Button(action: onResumeChapter) {
                        Label("云端续读：\(item.cloudChapterTitle)", systemImage: "book.pages")
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }

                Spacer(minLength: 2)

                HStack(spacing: 8) {
                    Text("#\(item.id)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    if showSyncBadge {
                        Label(
                            item.hasSyncedToCloud ? "云端同步" : "仅本地",
                            systemImage: item.hasSyncedToCloud ? "icloud.fill" : "internaldrive"
                        )
                        .font(.caption2)
                        .foregroundStyle(item.hasSyncedToCloud ? Color.accentColor : Color.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            vm.loadBook(inputOverride: item.id)
        }
        .onAppear {
            vm.ensureCoverLoaded(urlString: item.coverURL)
        }
    }

    private var coverView: some View {
        Group {
            if let img = vm.coverImageCache[item.coverURL] {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                    Image(systemName: "book.closed.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 84, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}
