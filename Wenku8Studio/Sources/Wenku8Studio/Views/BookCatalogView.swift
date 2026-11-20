import SwiftUI
import Wenku8Core

struct BookCatalogView: View {
    @EnvironmentObject var vm: StudioViewModel
    @State private var showFullDescription = false

    var body: some View {
        Group {
            if vm.isLoadingBook && vm.bookDetail == nil {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在从 \(vm.baseURL) 拉取书籍信息与目录...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let book = vm.bookDetail {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            bookHeaderCard(book)
                            if !book.recommendations.isEmpty {
                                recommendationsStrip(book)
                            }
                            catalogControlsBar(book)
                            volumesList(book)
                        }
                        .padding(20)
                        .padding(.bottom, 76)
                    }

                    bottomActionBar(book)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                }
            } else {
                emptyStateView
            }
        }
        .inspector(isPresented: $vm.showReviewsInspector) {
            ReviewsInspectorView()
                .inspectorColumnWidth(min: 340, ideal: 410, max: 520)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text("轻小说文库 · macOS 原生客户端与 EPUB 拼装工坊")
                .font(.title3.weight(.semibold))
            Text("在左侧输入书号（如 3115）或书籍网址，即可查看完整简介、可视化勾选分卷与章节、在线阅读或拼装定制 EPUB。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            HStack {
                Button("试一试：书号 3115") {
                    vm.loadBook(inputOverride: "3115")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bookHeaderCard(_ book: BookDetail) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Group {
                if let img = vm.coverPreviewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.15))
                        Image(systemName: "book.closed.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 126, height: 178)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title)
                            .font(.title2.weight(.bold))
                            .textSelection(.enabled)
                        HStack(spacing: 10) {
                            Button {
                                vm.loadAuthorWorks(author: book.author)
                            } label: {
                                Label(book.author, systemImage: "person.fill")
                            }
                            .buttonStyle(.link)

                            if !book.publisher.isEmpty {
                                badge(book.publisher, color: .blue)
                            }
                            if !book.status.isEmpty {
                                badge(book.status, color: book.status.contains("完结") ? .green : .orange)
                            }
                            badge("书号 \(book.bookId)", color: .gray)
                        }
                    }
                    Spacer()
                    Button {
                        vm.toggleBookmark(book)
                    } label: {
                        Label(
                            vm.isBookmarked(book.bookId) ? "已收藏" : "加入书架",
                            systemImage: vm.isBookmarked(book.bookId) ? "bookmark.fill" : "bookmark"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 16) {
                    if !book.wordCount.isEmpty {
                        Label(book.wordCount, systemImage: "character.book.closed")
                    }
                    if !book.lastUpdated.isEmpty {
                        Label("更新 \(book.lastUpdated)", systemImage: "calendar")
                    }
                    if !book.popularity.isEmpty {
                        Label(book.popularity, systemImage: "flame")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !book.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(book.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }

                if !book.description.isEmpty {
                    Text(book.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(showFullDescription ? nil : 3)
                        .onTapGesture { showFullDescription.toggle() }
                }

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            vm.openReviewsInspectorForCurrentBook()
                        } label: {
                            Label(vm.showReviewsInspector ? "收起/查看书评" : "查看书评", systemImage: "bubble.left.and.bubble.right")
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            vm.showReviewsInspector ? .regular.tint(.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
                            in: .capsule
                        )

                        Button {
                            vm.loadAuthorWorks(author: book.author)
                        } label: {
                            Label("同作者作品", systemImage: "person.2")
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)

                        Button {
                            vm.scrollToAssemblyToken = UUID()
                            vm.selectedSection = .settings
                        } label: {
                            Label("拼装设置", systemImage: "slider.horizontal.3")
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)

                        Spacer()
                        Text("来源：\(book.baseURL.replacingOccurrences(of: "https://", with: ""))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.callout)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func recommendationsStrip(_ book: BookDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("同分类推荐（点击直达）")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(book.recommendations) { rec in
                        Button {
                            vm.loadBook(inputOverride: rec.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: rec.isCompleted ? "checkmark.seal.fill" : "book.fill")
                                    .foregroundStyle(rec.isCompleted ? .green : .accentColor)
                                Text(rec.title)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func catalogControlsBar(_ book: BookDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("分卷与章节目录（共 \(book.volumes.count) 卷）")
                    .font(.headline)
                Spacer()
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("全选") { vm.selectAllChapters() }
                        Button("清空") { vm.clearSelection() }
                        Button("反选") { vm.invertSelection() }
                        Button("仅含插图卷") { vm.selectIllustratedVolumesOnly() }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    GlassInputField(
                        icon: "magnifyingglass",
                        placeholder: "按章节名过滤...",
                        text: $vm.chapterSearchQuery
                    )
                    .frame(maxWidth: 230)

                    GlassInputField(
                        icon: "number",
                        placeholder: "按卷号勾选（如 1-3 或 1,2,4）",
                        text: $vm.volumeRangeInput,
                        onSubmit: { vm.applyVolumeRangeSelection() }
                    )
                    .frame(maxWidth: 250)

                    Button("应用卷号") {
                        vm.applyVolumeRangeSelection()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)

                    Spacer()

                    GlassSegmentedControl(selection: $vm.assemblyConfig.exportMode, items: ExportMode.allCases)
                        .frame(maxWidth: 290)
                }
            }
        }
    }

    private func volumesList(_ book: BookDetail) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(book.volumes) { vol in
                let filteredChaps = filteredChapters(for: vol)
                if !filteredChaps.isEmpty || vm.chapterSearchQuery.isEmpty {
                    VolumeSectionCard(
                        volume: vol,
                        chapters: filteredChaps,
                        selectionState: vm.volumeSelectionState(vol),
                        isExpanded: Binding(
                            get: { vm.expandedVolumeIds.contains(vol.id) || !vm.chapterSearchQuery.isEmpty },
                            set: { expand in
                                if expand { vm.expandedVolumeIds.insert(vol.id) }
                                else { vm.expandedVolumeIds.remove(vol.id) }
                            }
                        ),
                        selectedChapterIds: vm.selectedChapterIds,
                        onToggleVolume: { vm.toggleVolume(vol) },
                        onToggleChapter: { vm.toggleChapter($0) },
                        onPreviewChapter: { vm.openChapterInReader($0) }
                    )
                }
            }
        }
    }

    private func filteredChapters(for vol: VolumeItem) -> [ChapterItem] {
        let q = vm.chapterSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return vol.chapters }
        return vol.chapters.filter { $0.title.lowercased().contains(q) }
    }

    private func bottomActionBar(_ book: BookDetail) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已选 \(vm.selectedVolumesCount) 卷 · \(vm.selectedBodyChaptersCount) 个正文章节")
                        .font(.callout.weight(.medium))
                        .contentTransition(.numericText())
                    Text("输出至：\(vm.outputDirectoryPath)（\(vm.assemblyConfig.exportMode.rawValue)）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if vm.isDownloading {
                    ProgressView(value: vm.progressFraction)
                        .frame(width: 140)
                    Button("取消下载") {
                        vm.cancelDownload()
                    }
                    .buttonStyle(.glass)
                } else {
                    Button {
                        vm.startDownloadSelected()
                    } label: {
                        Label("下载并拼装 EPUB", systemImage: "arrow.down.doc.fill")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(vm.selectedChapterIds.isEmpty)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct VolumeSectionCard: View {
    let volume: VolumeItem
    let chapters: [ChapterItem]
    let selectionState: Int
    @Binding var isExpanded: Bool
    let selectedChapterIds: Set<String>
    let onToggleVolume: () -> Void
    let onToggleChapter: (ChapterItem) -> Void
    let onPreviewChapter: (ChapterItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onToggleVolume) {
                    Image(systemName: selectionIcon)
                        .font(.title3)
                        .foregroundStyle(selectionState == 0 ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("[\(volume.index)] \(volume.title)")
                            .font(.headline)
                        if volume.hasIllustrationChapter {
                            Text("含彩插")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(.purple)
                                .background(Color.purple.opacity(0.12), in: Capsule())
                        }
                        Spacer()
                        Text("\(volume.chapters.count) 章")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if isExpanded {
                Divider()
                VStack(spacing: 0) {
                    ForEach(chapters) { chap in
                        HStack(spacing: 10) {
                            Button {
                                onToggleChapter(chap)
                            } label: {
                                Image(systemName: selectedChapterIds.contains(chap.id) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedChapterIds.contains(chap.id) ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)

                            Text(chap.title)
                                .font(.callout)
                                .foregroundStyle(chap.isIllustrationChapter ? .purple : .primary)

                            if chap.isIllustrationChapter {
                                Text("插图页")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                            }

                            Spacer()

                            Button {
                                onPreviewChapter(chap)
                            } label: {
                                Label("阅读", systemImage: "eye")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)

                        if chap.id != chapters.last?.id {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var selectionIcon: String {
        switch selectionState {
        case 2: return "checkmark.square.fill"
        case 1: return "minus.square.fill"
        default: return "square"
        }
    }
}
