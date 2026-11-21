import SwiftUI
import Wenku8Core

struct DiscoveryView: View {
    @EnvironmentObject var vm: StudioViewModel

    private let quickChannels: [(title: String, path: String, icon: String)] = [
        ("总点击榜", "/modules/article/toplist.php?sort=allvisit", "flame.fill"),
        ("最近更新", "/modules/article/toplist.php?sort=lastupdate", "clock.arrow.circlepath"),
        ("总推荐榜", "/modules/article/toplist.php?sort=allvote", "hand.thumbsup.fill"),
        ("总收藏榜", "/modules/article/toplist.php?sort=goodnum", "bookmark.fill"),
        ("周点击榜", "/modules/article/toplist.php?sort=weekvisit", "chart.line.uptrend.xyaxis"),
        ("月点击榜", "/modules/article/toplist.php?sort=monthvisit", "calendar"),
        ("新书一览", "/modules/article/toplist.php?sort=postdate", "sparkle"),
        ("字数排行", "/modules/article/toplist.php?sort=size", "text.word.spacing"),
        ("完结专区", "/modules/article/articlelist.php?fullflag=1", "checkmark.seal.fill"),
        ("动画化作品", "/modules/article/toplist.php?sort=anime", "sparkles.tv"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            discoveryHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if vm.showTagBrowser {
                        tagBrowserCard
                    }

                    if let notice = vm.discoveryNotice {
                        noticeCard(notice)
                    }

                    if !vm.discoveryBooks.isEmpty {
                        sectionHeader(vm.discoveryTitle, count: vm.discoveryBooks.count)
                        discoveryGrid(vm.discoveryBooks)
                        if vm.discoveryTotalPages > 1 {
                            paginationBar
                        }
                    } else if let current = vm.bookDetail, !current.recommendations.isEmpty {
                        sectionHeader("关联推荐 · 来自《\(current.title)》", count: current.recommendations.count)
                        recommendationsGrid(current.recommendations)
                    } else {
                        emptyDiscoveryPrompt
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            if vm.discoveryBooks.isEmpty && vm.activeDiscoverySort.isEmpty && !vm.isLoadingDiscovery {
                vm.loadDiscoveryList(title: "总点击榜", path: "/modules/article/toplist.php?sort=allvisit")
            }
        }
    }

    private var discoveryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    GlassInputField(
                        icon: "magnifyingglass",
                        placeholder: "搜索轻小说书名、作者名或输入书号...",
                        text: $vm.searchQuery,
                        onSubmit: { vm.performDiscoverySearch() }
                    )

                    GlassSegmentedControl(selection: $vm.searchScope, items: SearchScope.allCases)
                        .frame(width: 218)

                    Button {
                        vm.performDiscoverySearch()
                    } label: {
                        if vm.isLoadingDiscovery {
                            ProgressView().controlSize(.small)
                                .padding(.horizontal, 10)
                        } else {
                            Text("搜索")
                                .padding(.horizontal, 10)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(vm.isLoadingDiscovery || vm.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                vm.showTagBrowser.toggle()
                            }
                            if vm.showTagBrowser && vm.tagGroups.isEmpty {
                                vm.loadTagGroups()
                            }
                        } label: {
                            Label("Tags 标签云", systemImage: "tag.fill")
                                .font(.callout)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(vm.showTagBrowser || vm.selectedTag != nil ? Color.accentColor : Color.primary)
                        .glassEffect(
                            (vm.showTagBrowser || vm.selectedTag != nil) ? .regular.tint(.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
                            in: .capsule
                        )

                        ForEach(quickChannels, id: \.path) { channel in
                            let isActive = vm.activeDiscoverySort == channel.path
                            Button {
                                vm.loadDiscoveryList(title: channel.title, path: channel.path)
                            } label: {
                                Label(channel.title, systemImage: channel.icon)
                                    .font(.callout)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                            .glassEffect(
                                isActive ? .regular.tint(.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
                                in: .capsule
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func noticeCard(_ notice: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: vm.discoveryRequiresCookie ? "person.badge.key.fill" : "info.circle.fill")
                .font(.title3)
                .foregroundStyle(vm.discoveryRequiresCookie ? .orange : .blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(vm.discoveryRequiresCookie ? "需要登录账号以访问全站搜索与榜单" : "提示")
                    .font(.headline)
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vm.discoveryRequiresCookie {
                Button("前往设置登录") {
                    vm.selectedSection = .settings
                }
                .buttonStyle(.glassProminent)
                Button("网页登录") {
                    vm.showWebLoginSheet = true
                }
                .buttonStyle(.glass)
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(.orange.opacity(0.12)), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.title3.weight(.bold))
            Text("\(count) 本")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
            if vm.discoveryTotalPages > 1 {
                Text("第 \(vm.discoveryPage) / \(vm.discoveryTotalPages) 页")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var paginationBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Button {
                vm.loadDiscoveryPage(vm.discoveryPage - 1)
            } label: {
                Label("上一页", systemImage: "chevron.left")
            }
            .buttonStyle(.glass)
            .disabled(vm.discoveryPage <= 1 || vm.isLoadingDiscovery)

            Text("第 \(vm.discoveryPage) / \(vm.discoveryTotalPages) 页")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                vm.loadDiscoveryPage(vm.discoveryPage + 1)
            } label: {
                Label("下一页", systemImage: "chevron.right")
            }
            .buttonStyle(.glass)
            .disabled(vm.discoveryPage >= vm.discoveryTotalPages || vm.isLoadingDiscovery)
            Spacer()
        }
        .padding(.top, 6)
    }

    private var tagBrowserCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("官方 Tags 云集", systemImage: "tag.circle.fill")
                    .font(.headline)
                Spacer()
                Picker("排序", selection: $vm.tagSortOption) {
                    ForEach(TagSortOption.allCases) { opt in
                        Text(opt.displayName).tag(opt)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .onChange(of: vm.tagSortOption) { _, newSort in
                    if let tag = vm.selectedTag {
                        vm.loadBooksByTag(tag, sort: newSort, page: 1)
                    }
                }

                Button("刷新") {
                    vm.loadTagGroups()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            if vm.isLoadingTags {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在拉取标签云...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if vm.tagGroups.isEmpty {
                Text("暂无标签数据（需要登录后从 wenku8 拉取 Tags 分类）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(vm.tagGroups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(group.tags, id: \.self) { tag in
                                        let active = vm.selectedTag == tag
                                        Button {
                                            vm.loadBooksByTag(tag, sort: vm.tagSortOption, page: 1)
                                        } label: {
                                            Text(tag)
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(active ? Color.white : Color.primary)
                                        .background(
                                            active ? Color.accentColor : Color.secondary.opacity(0.12),
                                            in: Capsule()
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func discoveryGrid(_ items: [AuthorBookItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 500), spacing: 14)], spacing: 14) {
            ForEach(items) { item in
                BookItemCard(
                    item: BookCardItem(authorItem: item),
                    showBookmarkButton: true,
                    onToggleBookmark: {
                        vm.toggleBookmarkFromAuthorItem(item)
                    }
                )
            }
        }
    }

    private func recommendationsGrid(_ items: [RecommendedBook]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14)], spacing: 14) {
            ForEach(items) { rec in
                RecommendedBookCard(rec: rec)
            }
        }
    }

    private var emptyDiscoveryPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text("探索轻小说文库")
                .font(.title3.weight(.semibold))
            Text("可直接搜索作者名或书号，也可点击上方榜单发现热门作品与完结好书。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack(spacing: 10) {
                Button("搜索作者「猫玄」") {
                    vm.loadAuthorWorks(author: "猫玄")
                }
                .buttonStyle(.glassProminent)

                Button("查看书号 3115") {
                    vm.loadBook(inputOverride: "3115")
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct RecommendedBookCard: View {
    @EnvironmentObject var vm: StudioViewModel
    let rec: RecommendedBook
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = vm.coverImageCache[rec.coverURL] {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.15))
                            Image(systemName: "book.closed.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if rec.isCompleted {
                    Text("已完结")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }

            Text(rec.title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)

            Text("书号 \(rec.id)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
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
            vm.loadBook(inputOverride: rec.id)
        }
        .onAppear {
            vm.ensureCoverLoaded(urlString: rec.coverURL)
        }
    }
}
