import SwiftUI
import Wenku8Core

struct SettingsAndAssemblyView: View {
    @EnvironmentObject var vm: StudioViewModel
    private let builder = EPUBBuilder()

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section("站点与自动回退") {
                    Picker("预设站点", selection: $vm.baseURL) {
                        Text("备用主站（推荐）：https://www.wenku8.cc").tag("https://www.wenku8.cc")
                        Text("原主站（受限自动回退）：https://www.wenku8.net").tag("https://www.wenku8.net")
                    }

                    GlassInputField(
                        icon: "globe",
                        placeholder: "自定义站点地址（如 https://www.wenku8.cc）",
                        text: $vm.baseURL
                    )

                    Text("当默认站点 https://www.wenku8.cc 无法连接时，客户端会自动尝试回退主站 https://www.wenku8.net。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("账号 Cookie（可选，用于解锁全站搜索与榜单）") {
                    VStack(alignment: .leading, spacing: 10) {
                        GlassInputField(
                            icon: "key.horizontal",
                            placeholder: "粘贴 wenku8 Cookie（格式：jieqiUserInfo=...; PHPSESSID=...）",
                            text: $vm.customCookie
                        )

                        let diag = vm.cookieDiagnostic
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: diag.isLikelyValidFormat ? "checkmark.seal.fill" : (diag.isForeignSiteCookie ? "exclamationmark.triangle.fill" : "info.circle"))
                                .foregroundStyle(diag.isLikelyValidFormat ? .green : (diag.isForeignSiteCookie ? .orange : .secondary))
                            Text(diag.message)
                                .font(.caption)
                                .foregroundStyle(diag.isForeignSiteCookie ? .orange : .secondary)
                        }

                        if let verifyMsg = vm.cookieVerifyMessage {
                            HStack(spacing: 8) {
                                Image(systemName: (vm.cookieVerifyPassed == true) ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle((vm.cookieVerifyPassed == true) ? .green : .red)
                                Text(verifyMsg)
                                    .font(.caption)
                                    .foregroundStyle((vm.cookieVerifyPassed == true) ? .green : .red)
                            }
                        }

                        if let profile = vm.userProfile, !profile.username.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(profile.nickname.isEmpty ? profile.username : profile.nickname) (\(profile.level.isEmpty ? "会员" : profile.level))")
                                        .font(.callout.weight(.semibold))
                                    Text("积分 \(profile.holdingPoints.isEmpty ? "-" : profile.holdingPoints) · 经验 \(profile.experienceValue.isEmpty ? "-" : profile.experienceValue) · 每日推荐 \(profile.dailyVoteQuota.isEmpty ? "-" : profile.dailyVoteQuota) 次 · 书架上限 \(profile.bookcaseCapacity.isEmpty ? "-" : profile.bookcaseCapacity) 本")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("打开书架") {
                                    vm.selectedSection = .bookshelf
                                    vm.syncBookshelfBidirectionally(silent: true)
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                            }
                            .padding(10)
                            .glassEffect(.regular.tint(.green.opacity(0.10)), in: RoundedRectangle(cornerRadius: 10))
                        }

                        GlassEffectContainer(spacing: 10) {
                            HStack(spacing: 10) {
                                Button {
                                    vm.showWebLoginSheet = true
                                } label: {
                                    Label("网页登录自动获取 Cookie", systemImage: "safari")
                                }
                                .buttonStyle(.glassProminent)

                                Button {
                                    vm.testCookieValidity()
                                } label: {
                                    if vm.isTestingCookie {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("检测 Cookie 有效性", systemImage: "checkmark.shield")
                                    }
                                }
                                .buttonStyle(.glass)
                                .disabled(vm.isTestingCookie)

                                Button {
                                    Task { await vm.refreshCookieKeepAlive(silent: false) }
                                } label: {
                                    if vm.isRefreshingCookie {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("立即刷新续期", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                }
                                .buttonStyle(.glass)
                                .disabled(vm.isRefreshingCookie || vm.customCookie.isEmpty)

                                if !vm.customCookie.isEmpty {
                                    Button("清空") {
                                        vm.clearSavedCookie()
                                    }
                                    .buttonStyle(.glass)
                                }
                            }
                        }

                        Divider().padding(.vertical, 2)

                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("登录后自动定时保活并动态刷新 Cookie", isOn: $vm.autoRefreshCookieEnabled)
                                .onChange(of: vm.autoRefreshCookieEnabled) { _, _ in
                                    vm.rescheduleCookieRefresh()
                                }

                            if vm.autoRefreshCookieEnabled {
                                HStack(spacing: 12) {
                                    Text("动态刷新间隔")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("刷新间隔", selection: $vm.cookieRefreshIntervalMinutes) {
                                        Text("5 分钟").tag(5)
                                        Text("10 分钟").tag(10)
                                        Text("15 分钟").tag(15)
                                        Text("30 分钟").tag(30)
                                        Text("60 分钟").tag(60)
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 340)
                                    .onChange(of: vm.cookieRefreshIntervalMinutes) { _, _ in
                                        vm.rescheduleCookieRefresh()
                                    }
                                }
                            }

                            HStack(spacing: 14) {
                                if let lastAt = vm.lastCookieRefreshAt {
                                    Label(
                                        "上次刷新：\(lastAt.formatted(date: .omitted, time: .shortened))",
                                        systemImage: "clock.badge.checkmark"
                                    )
                                }
                                if let nextAt = vm.nextCookieRefreshAt, vm.autoRefreshCookieEnabled {
                                    Label(
                                        "下次刷新：\(nextAt.formatted(date: .omitted, time: .shortened))",
                                        systemImage: "timer"
                                    )
                                }
                                if let refreshStatus = vm.lastCookieRefreshStatus, !refreshStatus.isEmpty {
                                    Text(refreshStatus)
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Text("手动获取说明：在浏览器打开 www.wenku8.cc 并登录后，按 ⌘⌥I → Application → Cookies → https://www.wenku8.cc，复制含 jieqiUserInfo 和 PHPSESSID 的键值（勿粘贴微软/必应 MUID 等其他站点 Cookie）。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("性能与输出目录") {
                    Stepper("图片并发下载线程数：\(vm.maxConcurrency)", value: $vm.maxConcurrency, in: 1...16)

                    HStack {
                        Text("章节请求间隔：\(String(format: "%.2f", vm.politeDelaySeconds)) 秒")
                            .monospacedDigit()
                        Spacer()
                        Slider(value: $vm.politeDelaySeconds, in: 0...1.5, step: 0.05)
                            .frame(width: 240)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                    }

                    HStack {
                        VStack(alignment: .leading) {
                            Text("EPUB 下载目录")
                            Text(vm.outputDirectoryPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("更改目录...") {
                            vm.chooseOutputDirectory()
                        }
                        .buttonStyle(.glass)
                    }
                }

                Section {
                    Picker("EPUB 规范版本", selection: $vm.assemblyConfig.epubVersion) {
                        ForEach(EPUBVersion.allCases) { ver in
                            Text(ver.rawValue).tag(ver)
                        }
                    }
                    Picker("分卷导出策略", selection: $vm.assemblyConfig.exportMode) {
                        ForEach(ExportMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Toggle("生成书籍简介扉页（含封面、标签、字数、完整简介）", isOn: $vm.assemblyConfig.includeInfoPage)
                } header: {
                    Text("EPUB 拼装 · 格式与扉页")
                        .id("assemblySection")
                }

                Section("EPUB 拼装 · 封面与彩插") {
                    Toggle("包含封面页", isOn: $vm.assemblyConfig.includeCover)
                    if vm.assemblyConfig.includeCover {
                        Picker("封面来源", selection: $vm.assemblyConfig.coverSource) {
                            ForEach(CoverSourceMode.allCases) { src in
                                Text(src.rawValue).tag(src)
                            }
                        }

                        if vm.assemblyConfig.coverSource == .customLocalFile {
                            HStack {
                                Text(vm.assemblyConfig.customCoverPath.isEmpty ? "未选择本地封面文件" : vm.assemblyConfig.customCoverPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Button("选择本地封面...") {
                                    vm.chooseCustomCoverImage()
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }

                    Picker("彩插排版方式", selection: $vm.assemblyConfig.colorLayout) {
                        ForEach(ColorLayoutMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    if vm.assemblyConfig.colorLayout != .skipColor {
                        Picker("彩插章节位置", selection: $vm.assemblyConfig.colorPlacement) {
                            ForEach(ColorPlacement.allCases) { pos in
                                Text(pos.rawValue).tag(pos)
                            }
                        }
                        Toggle("自动过滤正文中已出现过的插图（避免重复）", isOn: $vm.assemblyConfig.dedupColorImages)

                        HStack {
                            Text("额外追加本地彩页（\(vm.assemblyConfig.extraColorImagePaths.count) 张）")
                            Spacer()
                            if !vm.assemblyConfig.extraColorImagePaths.isEmpty {
                                Button("清空") {
                                    vm.assemblyConfig.extraColorImagePaths.removeAll()
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                            }
                            Button("添加图片...") {
                                vm.addExtraColorImages()
                            }
                            .buttonStyle(.glass)
                        }

                        ForEach(vm.assemblyConfig.extraColorImagePaths, id: \.self) { path in
                            HStack {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .font(.caption)
                                Spacer()
                                Button {
                                    vm.assemblyConfig.extraColorImagePaths.removeAll { $0 == path }
                                } label: {
                                    Image(systemName: "xmark.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("EPUB 拼装 · 正文清洗与样式") {
                    Toggle("清理章节开头的录入组/图源/修图声明行", isOn: $vm.assemblyConfig.cleanCreditsHeader)

                    HStack {
                        Text("段首缩进：\(String(format: "%.1f", vm.assemblyConfig.textIndentEm)) em")
                            .monospacedDigit()
                        Spacer()
                        Slider(value: $vm.assemblyConfig.textIndentEm, in: 0...3, step: 0.5)
                            .frame(width: 240)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                    }

                    HStack {
                        Text("正文行高：\(String(format: "%.2f", vm.assemblyConfig.lineHeight))")
                            .monospacedDigit()
                        Spacer()
                        Slider(value: $vm.assemblyConfig.lineHeight, in: 1.3...2.2, step: 0.05)
                            .frame(width: 240)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                    }

                    HStack {
                        Text("段落间距：\(String(format: "%.2f", vm.assemblyConfig.paragraphSpacingEm)) em")
                            .monospacedDigit()
                        Spacer()
                        Slider(value: $vm.assemblyConfig.paragraphSpacingEm, in: 0...1.5, step: 0.1)
                            .frame(width: 240)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                    }
                }

                Section("EPUB 拼装 · 元数据覆写与命名模板") {
                    GlassInputField(icon: "textformat", placeholder: "自定义书名（留空使用原书名）", text: $vm.assemblyConfig.customTitleOverride)
                    GlassInputField(icon: "person", placeholder: "自定义作者（留空使用原作者）", text: $vm.assemblyConfig.customAuthorOverride)
                    GlassInputField(icon: "doc.badge.gearshape", placeholder: "文件名模板（{title} {volume} {index} {author} {id}）", text: $vm.assemblyConfig.filenameTemplate)

                    HStack {
                        Text("命名预览")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(previewFilename).epub")
                            .font(.callout.monospaced())
                            .foregroundStyle(Color.accentColor)
                    }

                    GlassEffectContainer(spacing: 10) {
                        HStack {
                            Button("恢复默认拼装配置") {
                                vm.assemblyConfig = AssemblyConfig()
                                vm.savePersistedState()
                            }
                            .buttonStyle(.glass)
                            Spacer()
                            Button("应用并保存全部设置") {
                                Task {
                                    await vm.syncClientSettings()
                                    vm.statusBanner = "设置与拼装参数已保存"
                                }
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: vm.scrollToAssemblyToken) { _, newToken in
                if newToken != nil {
                    withAnimation {
                        proxy.scrollTo("assemblySection", anchor: .top)
                    }
                }
            }
            .onChange(of: vm.baseURL) { _, _ in
                Task { await vm.syncClientSettings() }
            }
            .onChange(of: vm.maxConcurrency) { _, _ in
                vm.savePersistedState()
            }
            .onChange(of: vm.assemblyConfig) { _, _ in
                vm.savePersistedState()
            }
        }
    }

    private var previewFilename: String {
        let title = vm.assemblyConfig.customTitleOverride.isEmpty
            ? (vm.bookDetail?.title ?? "关于我帮助迷路小女孩后...")
            : vm.assemblyConfig.customTitleOverride
        let author = vm.assemblyConfig.customAuthorOverride.isEmpty
            ? (vm.bookDetail?.author ?? "猫玄")
            : vm.assemblyConfig.customAuthorOverride
        let bookId = vm.bookDetail?.bookId ?? "3115"
        return builder.renderFilename(
            template: vm.assemblyConfig.filenameTemplate,
            title: title,
            volume: vm.assemblyConfig.exportMode == .mergedSingle ? "合集" : "第一卷",
            index: 1,
            author: author,
            bookId: bookId
        )
    }
}
