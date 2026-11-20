import SwiftUI
import Wenku8Core

struct BookshelfHistoryView: View {
    @EnvironmentObject var vm: StudioViewModel
    @State private var filterScope: ShelfScope = .all
    @State private var filterText: String = ""

    enum ShelfScope: String, CaseIterable, Identifiable {
        case all = "全部"
        case bookmarks = "本地书架"
        case history = "最近浏览"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if filterScope == .all || filterScope == .bookmarks {
                        shelfSection(
                            title: "本地书架",
                            icon: "bookmark.fill",
                            items: filtered(vm.bookmarks),
                            isHistory: false
                        )
                    }

                    if filterScope == .all || filterScope == .history {
                        shelfSection(
                            title: "最近浏览",
                            icon: "clock.fill",
                            items: filtered(vm.history),
                            isHistory: true
                        )
                    }
                }
                .padding(20)
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
                .frame(maxWidth: 250)

                Spacer()

                if !vm.history.isEmpty {
                    Button(role: .destructive) {
                        withAnimation {
                            vm.clearHistory()
                        }
                    } label: {
                        Label("清空最近浏览", systemImage: "trash")
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

    private func filtered(_ items: [BookmarkEntry]) -> [BookmarkEntry] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(q) || $0.author.lowercased().contains(q) || $0.id.contains(q)
        }
    }

    @ViewBuilder
    private func shelfSection(title: String, icon: String, items: [BookmarkEntry], isHistory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.title3.weight(.bold))
                Text("\(items.count)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                Spacer()
            }

            if items.isEmpty {
                Text(isHistory ? "暂无最近浏览记录" : "暂未收藏书籍，可在书籍详情页点击「加入书架」")
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
                            showBookmarkButton: isHistory,
                            deleteTooltip: isHistory ? "删除此条浏览记录" : "移出书架",
                            onDelete: {
                                withAnimation {
                                    if isHistory {
                                        vm.removeHistoryItem(id: entry.id)
                                    } else {
                                        vm.removeBookmark(id: entry.id)
                                    }
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
