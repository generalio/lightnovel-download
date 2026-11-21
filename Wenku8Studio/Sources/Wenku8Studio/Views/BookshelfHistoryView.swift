import SwiftUI
import Wenku8Core

struct BookshelfHistoryView: View {
    @EnvironmentObject var vm: StudioViewModel
    @State private var filterScope: ShelfScope = .all
    @State private var filterText: String = ""

    enum ShelfScope: String, CaseIterable, Identifiable {
        case all = "全部"
        case bookshelf = "书架"
        case history = "最近浏览"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if filterScope == .all || filterScope == .bookshelf {
                        unifiedBookshelfSection
                    }

                    if filterScope == .all || filterScope == .history {
                        historySection
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            if vm.isCloudSessionAvailable && !vm.isSyncingBookshelf {
                vm.syncBookshelfBidirectionally(silent: true)
            }
        }
    }

    private var headerBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                GlassSegmentedControl(selection: $filterScope, items: ShelfScope.allCases)
                    .frame(maxWidth: 300)

                GlassInputField(
                    icon: "line.3.horizontal.decrease.circle",
                    placeholder: "筛选书名或作者...",
                    text: $filterText
                )
                .frame(maxWidth: 240)

                Spacer()

                Button {
                    vm.syncBookshelfBidirectionally(silent: false)
                } label: {
                    if vm.isSyncingBookshelf {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("双向同步", systemImage: "arrow.triangle.2.circlepath.icloud")
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(vm.isSyncingBookshelf)
                .help("已登录时自动与 wenku8 云端个人书架双向同步")

                if !vm.history.isEmpty {
                    Button(role: .destructive) {
                        withAnimation {
                            vm.clearHistory()
                        }
                    } label: {
                        Label("清空浏览", systemImage: "trash")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private func filteredBookmarks() -> [BookmarkEntry] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return vm.bookmarks.filter { entry in
            let matchesGroup: Bool
            if vm.activeCloudGroupFilter == "all" || vm.cloudBookcaseGroups.count <= 1 {
                matchesGroup = true
            } else {
                matchesGroup = entry.cloudGroupId == vm.activeCloudGroupFilter
            }
            guard matchesGroup else { return false }
            guard !q.isEmpty else { return true }
            return entry.title.lowercased().contains(q) || entry.author.lowercased().contains(q) || entry.id.contains(q)
        }
    }

    private func filteredHistory() -> [BookmarkEntry] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return vm.history }
        return vm.history.filter {
            $0.title.lowercased().contains(q) || $0.author.lowercased().contains(q) || $0.id.contains(q)
        }
    }

    private var unifiedBookshelfSection: some View {
        let items = filteredBookmarks()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("书架", systemImage: "books.vertical.fill")
                    .font(.title3.weight(.bold))
                Text("\(items.count)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())

                if vm.isCloudSessionAvailable {
                    Label("云端双向同步", systemImage: "icloud.fill")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(.green)
                        .background(Color.green.opacity(0.14), in: Capsule())
                } else {
                    Label("离线本地模式", systemImage: "internaldrive")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(.orange)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                }

                if !vm.cloudCapacityTip.isEmpty {
                    Text(vm.cloudCapacityTip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let lastSync = vm.lastBookshelfSyncAt {
                    Text("同步于 \(lastSync.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !vm.isCloudSessionAvailable {
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Text(vm.bookshelfSyncNotice ?? "当前未登录，新增收藏将暂存本地；登录后会自动推送到 wenku8 云端并双向同步。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("网页登录") {
                        vm.showWebLoginSheet = true
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(.orange.opacity(0.08)), in: RoundedRectangle(cornerRadius: 12))
            }

            if vm.cloudBookcaseGroups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            groupChip(id: "all", title: "全部分组")
                            ForEach(vm.cloudBookcaseGroups) { group in
                                groupChip(id: group.id, title: group.title)
                            }
                        }
                    }
                }
            }

            if items.isEmpty {
                Text("书架暂无藏书，可在书籍详情页或发现页点击「加入书架」（已登录时直推云端）")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 500), spacing: 14)], spacing: 14) {
                    ForEach(items) { entry in
                        let live = (vm.bookDetail?.bookId == entry.id) ? vm.bookDetail : nil
                        BookItemCard(
                            item: BookCardItem(entry: entry, liveDetail: live),
                            showBookmarkButton: false,
                            showSyncBadge: true,
                            deleteTooltip: vm.isCloudSessionAvailable ? "移出书架（同步从云端删除）" : "移出本地书架",
                            onDelete: {
                                withAnimation {
                                    vm.removeBookmark(id: entry.id)
                                }
                            },
                            onResumeChapter: entry.cloudChapterId.isEmpty ? nil : {
                                vm.openBookmarkChapter(entry)
                            },
                            cloudGroups: vm.isCloudSessionAvailable ? vm.cloudBookcaseGroups : [],
                            onMoveCloudGroup: { targetGroupId in
                                vm.moveBookmarkToCloudGroup(entry, toClassId: targetGroupId)
                            }
                        )
                    }
                }
            }
        }
    }

    private func groupChip(id: String, title: String) -> some View {
        let active = vm.activeCloudGroupFilter == id
        return Button {
            vm.activeCloudGroupFilter = id
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.accentColor : Color.primary)
        .glassEffect(
            active ? .regular.tint(.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
            in: .capsule
        )
    }

    private var historySection: some View {
        let items = filteredHistory()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("最近浏览", systemImage: "clock.fill")
                    .font(.title3.weight(.bold))
                Text("\(items.count)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                Spacer()
            }

            if items.isEmpty {
                Text("暂无最近浏览记录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 500), spacing: 14)], spacing: 14) {
                    ForEach(items) { entry in
                        let live = (vm.bookDetail?.bookId == entry.id) ? vm.bookDetail : nil
                        BookItemCard(
                            item: BookCardItem(entry: entry, liveDetail: live),
                            showBookmarkButton: true,
                            deleteTooltip: "删除此条浏览记录",
                            onDelete: {
                                withAnimation {
                                    vm.removeHistoryItem(id: entry.id)
                                }
                            },
                            onToggleBookmark: {
                                vm.toggleBookmarkFromEntry(entry)
                            }
                        )
                    }
                }
            }
        }
    }
}
