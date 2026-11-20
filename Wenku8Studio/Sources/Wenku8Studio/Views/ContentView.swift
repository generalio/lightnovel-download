import SwiftUI
import Wenku8Core

struct ContentView: View {
    @EnvironmentObject var vm: StudioViewModel

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 224, ideal: 248, max: 290)
        } detail: {
            VStack(spacing: 0) {
                topStatusBanners
                detailWorkspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $vm.showWebLoginSheet) {
            WebLoginSheet()
                .environmentObject(vm)
        }
        .onAppear {
            if vm.bookDetail == nil && !vm.bookInput.isEmpty {
                vm.loadBook()
            }
        }
    }

    private var sidebarContent: some View {
        List(selection: $vm.selectedSection) {
            Section("快速直达") {
                VStack(alignment: .leading, spacing: 8) {
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            GlassInputField(
                                icon: "number",
                                placeholder: "书号或网址 (如 3115)",
                                text: $vm.bookInput,
                                onSubmit: { vm.loadBook() }
                            )

                            Button {
                                vm.loadBook()
                            } label: {
                                if vm.isLoadingBook {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(vm.isLoadingBook)
                        }
                    }

                    Text("主选: \(vm.baseURL.replacingOccurrences(of: "https://", with: ""))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("工作区") {
                ForEach(SidebarSection.allCases) { section in
                    SidebarRowView(
                        section: section,
                        badgeCount: badgeCount(for: section),
                        isBusy: section == .tasks && vm.isDownloading
                    )
                    .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func badgeCount(for section: SidebarSection) -> Int {
        switch section {
        case .catalog: return vm.selectedBodyChaptersCount
        case .bookshelf: return vm.bookmarks.count + vm.history.count
        default: return 0
        }
    }

    @ViewBuilder
    private var topStatusBanners: some View {
        if vm.errorBanner != nil || vm.statusBanner != nil {
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 8) {
                    if let err = vm.errorBanner {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(err)
                                .font(.callout)
                                .lineLimit(2)
                            Spacer()
                            Button("关闭") { vm.errorBanner = nil }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.tint(.orange.opacity(0.18)), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let ok = vm.statusBanner {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(ok)
                                .font(.callout)
                            Spacer()
                            Button("打开目录") { vm.openOutputFolder() }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                            Button("关闭") { vm.statusBanner = nil }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.tint(.green.opacity(0.18)), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private var detailWorkspace: some View {
        switch vm.selectedSection {
        case .discovery:
            DiscoveryView()
        case .bookshelf:
            BookshelfHistoryView()
        case .catalog:
            BookCatalogView()
        case .reader:
            ReaderPreviewView()
        case .tasks:
            TasksAndLogsView()
        case .settings:
            SettingsAndAssemblyView()
        }
    }
}

private struct SidebarRowView: View, Equatable {
    let section: SidebarSection
    let badgeCount: Int
    let isBusy: Bool

    static func == (lhs: SidebarRowView, rhs: SidebarRowView) -> Bool {
        lhs.section == rhs.section && lhs.badgeCount == rhs.badgeCount && lhs.isBusy == rhs.isBusy
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 20, height: 20)
                .transaction { $0.animation = nil }

            Text(section.rawValue)
                .lineLimit(1)

            Spacer()

            if isBusy {
                ProgressView()
                    .controlSize(.mini)
            } else if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .transaction { $0.animation = nil }
    }
}
