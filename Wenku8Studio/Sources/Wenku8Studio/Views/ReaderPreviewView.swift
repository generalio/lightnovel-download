import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Wenku8Core

struct ReaderPreviewView: View {
    @EnvironmentObject var vm: StudioViewModel

    @State private var showTOCSidebar = false
    @State private var sidebarTab: ReaderSidebarTab = .toc
    @State private var showTypographyPopover = false
    @State private var lightboxImageIndex: Int? = nil

    @State private var readerViewportSize: CGSize = CGSize(width: 820, height: 640)
    @State private var paginatedPages: [ReaderPage] = []
    @State private var currentPageIndex: Int = 0
    @State private var pageTurnSignal: PageTurnSignal? = nil
    @State private var searchInChapterQuery: String = ""
    @State private var searchHits: [ReaderSearchHit] = []

    @State private var autoTurnEnabled: Bool = false
    @State private var autoTurnIntervalSeconds: Double = 12
    @State private var autoTurnTask: Task<Void, Never>?

    private enum ReaderSidebarTab: String, CaseIterable, Identifiable {
        case toc = "目录"
        case bookmarks = "书签"
        case search = "查找"
        var id: String { rawValue }
    }

    private var isDualSpreadActive: Bool {
        vm.readerDualPageEnabled && vm.readerPageMode != .scroll && readerViewportSize.width >= 860
    }

    var body: some View {
        HStack(spacing: 0) {
            if showTOCSidebar && !vm.isFocusReadingMode {
                leftSidebarDrawer
                    .frame(width: 274)
                Divider()
            }

            VStack(spacing: 0) {
                if !vm.isFocusReadingMode {
                    readerToolbar
                }

                if vm.isLoadingPreview {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在加载章节正文与插图...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(vm.readerTheme.backgroundColor)
                } else if let content = vm.previewChapter {
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            Group {
                                if vm.readerPageMode == .scroll {
                                    scrollReaderBody(content)
                                } else {
                                    SimulationPageReaderView(
                                        content: content,
                                        pages: paginatedPages,
                                        currentPageIndex: $currentPageIndex,
                                        externalTurnSignal: $pageTurnSignal,
                                        containerSize: geo.size,
                                        isDualPage: isDualSpreadActive,
                                        pageMode: vm.readerPageMode,
                                        onOpenLightbox: { idx in
                                            lightboxImageIndex = idx
                                        },
                                        onPreviousChapter: {
                                            if let prev = vm.adjacentChapter(offset: -1) {
                                                vm.openChapterInReader(prev, startAtLastPage: true)
                                            }
                                        },
                                        onNextChapter: {
                                            if let next = vm.adjacentChapter(offset: 1) {
                                                vm.openChapterInReader(next, startAtLastPage: false)
                                            }
                                        },
                                        onToggleFocus: {
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                vm.isFocusReadingMode.toggle()
                                            }
                                        }
                                    )
                                }
                            }

                            if vm.isFocusReadingMode {
                                focusModeFloatingBar(content: content)
                            } else if vm.readerPageMode != .scroll && paginatedPages.count > 1 {
                                compactPageProgressScrubber(content: content)
                            }
                        }
                        .onAppear {
                            readerViewportSize = geo.size
                            recomputePages(resetOrRestorePosition: true)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            if abs(newSize.width - readerViewportSize.width) > 4 || abs(newSize.height - readerViewportSize.height) > 4 {
                                readerViewportSize = newSize
                                recomputePages(resetOrRestorePosition: false)
                            }
                        }
                    }
                } else {
                    emptyReaderState
                }
            }
        }
        .onChange(of: vm.previewChapter?.chapter.id) { _, _ in
            recomputePages(resetOrRestorePosition: true)
            refreshSearchHits()
        }
        .onChange(of: paginationSignature) { _, _ in
            recomputePages(resetOrRestorePosition: false)
            refreshSearchHits()
            vm.savePersistedState()
        }
        .onChange(of: currentPageIndex) { _, newIdx in
            guard let chap = vm.previewChapter?.chapter, !paginatedPages.isEmpty else { return }
            let clamped = min(max(0, newIdx), paginatedPages.count - 1)
            vm.updateChapterProgressRatio(chapterId: chap.id, ratio: paginatedPages[clamped].progressRatio)
        }
        .onChange(of: vm.readerTheme) { _, _ in vm.savePersistedState() }
        .onChange(of: vm.readerPageMode) { _, _ in vm.savePersistedState() }
        .onChange(of: vm.readerDualPageEnabled) { _, _ in
            recomputePages(resetOrRestorePosition: false)
            vm.savePersistedState()
        }
        .onChange(of: autoTurnEnabled) { _, enabled in
            updateAutoTurnSchedule(enabled: enabled)
        }
        .onChange(of: autoTurnIntervalSeconds) { _, _ in
            if autoTurnEnabled {
                updateAutoTurnSchedule(enabled: true)
            }
        }
        .onDisappear {
            autoTurnTask?.cancel()
            autoTurnTask = nil
        }
        .background {
            // Hidden shortcut triggers for fluid keyboard page/chapter control
            Group {
                Button("") {
                    turnBackward()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button("") {
                    turnForward()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button("") {
                    turnForward()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("") {
                    withAnimation {
                        showTOCSidebar = true
                        sidebarTab = .search
                    }
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("") {
                    if vm.isFocusReadingMode {
                        withAnimation { vm.isFocusReadingMode = false }
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0.001)
        }
        .sheet(isPresented: Binding(
            get: { lightboxImageIndex != nil },
            set: { if !$0 { lightboxImageIndex = nil } }
        )) {
            if let content = vm.previewChapter, !content.imageURLs.isEmpty {
                ReaderImageLightboxView(
                    imageURLs: content.imageURLs,
                    imagesMap: vm.previewImages,
                    currentIndex: Binding(
                        get: { lightboxImageIndex ?? 0 },
                        set: { lightboxImageIndex = $0 }
                    ),
                    onClose: { lightboxImageIndex = nil }
                )
            }
        }
    }

    private var paginationSignature: String {
        "\(vm.readerFontFamily.rawValue)|\(vm.readerCustomFontName)|\(vm.readerFontSize)|\(vm.readerLineSpacing)|\(vm.readerParagraphSpacing)|\(vm.readerEdgePadding)|\(vm.readerIndentEnabled)|\(vm.readerScriptMode.rawValue)|\(isDualSpreadActive)"
    }

    private func recomputePages(resetOrRestorePosition: Bool) {
        guard let content = vm.previewChapter else {
            paginatedPages = []
            currentPageIndex = 0
            return
        }

        let prevRatio: Double
        if resetOrRestorePosition {
            if vm.readerStartAtEndOnOpen {
                prevRatio = 1.0
                vm.readerStartAtEndOnOpen = false
            } else {
                prevRatio = vm.lastReadPageRatioByChapter[content.chapter.id] ?? 0.0
            }
        } else if !paginatedPages.isEmpty {
            let clamped = min(max(0, currentPageIndex), paginatedPages.count - 1)
            prevRatio = paginatedPages[clamped].progressRatio
        } else {
            prevRatio = 0.0
        }

        let edgePad = CGFloat(vm.readerEdgePadding)
        let sheetWidth = max(360, readerViewportSize.width - edgePad * 2)
        let leafWidth = isDualSpreadActive ? (sheetWidth - 2) / 2 : sheetWidth
        let sheetHeight = max(280, readerViewportSize.height - 20)
        let innerHorizontalPad: CGFloat = isDualSpreadActive ? 60 : 80

        let textContainerSize = CGSize(
            width: max(220, leafWidth - innerHorizontalPad),
            height: max(200, sheetHeight - 92)
        )
        let config = ReaderPaginationConfig(
            fontFamily: vm.readerFontFamily,
            customFontName: vm.readerCustomFontName,
            fontSize: CGFloat(vm.readerFontSize),
            lineSpacing: CGFloat(vm.readerLineSpacing),
            paragraphSpacing: CGFloat(vm.readerParagraphSpacing),
            indentEnabled: vm.readerIndentEnabled,
            scriptMode: vm.readerScriptMode
        )

        let computed = ReaderPaginator.paginate(content: content, config: config, containerSize: textContainerSize)
        paginatedPages = computed

        if computed.isEmpty {
            currentPageIndex = 0
        } else {
            var targetIdx = Int(round(prevRatio * Double(max(0, computed.count - 1))))
            if isDualSpreadActive {
                targetIdx = (targetIdx / 2) * 2
            }
            currentPageIndex = min(max(0, targetIdx), computed.count - 1)
        }
    }

    private func refreshSearchHits() {
        searchHits = ReaderPaginator.search(searchInChapterQuery, in: paginatedPages)
    }

    private func turnForward() {
        if vm.readerPageMode == .scroll {
            if let next = vm.adjacentChapter(offset: 1) {
                vm.openChapterInReader(next)
            }
            return
        }
        pageTurnSignal = PageTurnSignal(id: UUID(), forward: true)
    }

    private func turnBackward() {
        if vm.readerPageMode == .scroll {
            if let prev = vm.adjacentChapter(offset: -1) {
                vm.openChapterInReader(prev)
            }
            return
        }
        pageTurnSignal = PageTurnSignal(id: UUID(), forward: false)
    }

    private func updateAutoTurnSchedule(enabled: Bool) {
        autoTurnTask?.cancel()
        autoTurnTask = nil
        guard enabled else { return }
        let interval = max(4, autoTurnIntervalSeconds)
        autoTurnTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                await MainActor.run {
                    if vm.readerPageMode != .scroll {
                        turnForward()
                    }
                }
            }
        }
    }

    // MARK: - Scroll Mode Body

    private func scrollReaderBody(_ content: ChapterContent) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: vm.readerParagraphSpacing) {
                    Color.clear
                        .frame(height: 1)
                        .id("readerTop")

                    Text(ReaderPaginator.convertScript(content.chapter.title, mode: vm.readerScriptMode))
                        .font(vm.readerFontFamily.swiftUIFont(
                            customFontName: vm.readerCustomFontName,
                            size: vm.readerFontSize + 7,
                            bold: true
                        ))
                        .foregroundStyle(vm.readerTheme.foregroundColor)
                        .padding(.bottom, 10)

                    ForEach(Array(content.tokens.enumerated()), id: \.offset) { _, token in
                        switch token {
                        case .paragraph(let text):
                            let converted = ReaderPaginator.convertScript(text, mode: vm.readerScriptMode)
                            Text(vm.readerIndentEnabled ? "　　\(converted)" : converted)
                                .font(vm.readerFontFamily.swiftUIFont(
                                    customFontName: vm.readerCustomFontName,
                                    size: vm.readerFontSize,
                                    bold: false
                                ))
                                .lineSpacing(vm.readerLineSpacing)
                                .foregroundStyle(vm.readerTheme.foregroundColor)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .image(let url):
                            if let img = vm.previewImages[url] {
                                Button {
                                    if let idx = content.imageURLs.firstIndex(of: url) {
                                        lightboxImageIndex = idx
                                    }
                                } label: {
                                    ZStack(alignment: .bottomTrailing) {
                                        Image(nsImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxWidth: min(vm.readerColumnWidth, 720))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.caption.weight(.semibold))
                                            .padding(7)
                                            .glassEffect(.regular, in: .circle)
                                            .padding(10)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .help("点击查看大图预览")
                            }
                        }
                    }

                    Divider().padding(.top, 24)
                    HStack {
                        if let prog = vm.readerProgressInfo() {
                            Text("阅读进度：第 \(prog.current) / \(prog.total) 章")
                                .font(.caption)
                                .foregroundStyle(vm.readerTheme.foregroundColor.opacity(0.6))
                        }
                        Spacer()
                        chapterNavigationButtons
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, max(24, CGFloat(vm.readerEdgePadding) + 20))
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(vm.readerTheme.backgroundColor)
            .onChange(of: content.chapter.id) { _, _ in
                scrollProxy.scrollTo("readerTop", anchor: .top)
            }
        }
    }

    // MARK: - Focus & Progress Overlays

    private func compactPageProgressScrubber(content: ChapterContent) -> some View {
        let maxIndex = Double(max(1, paginatedPages.count - 1))
        return HStack(spacing: 10) {
            Text("P.\(currentPageIndex + 1)/\(paginatedPages.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { Double(currentPageIndex) },
                    set: { val in
                        var target = Int(round(val))
                        if isDualSpreadActive {
                            target = (target / 2) * 2
                        }
                        currentPageIndex = min(max(0, target), max(0, paginatedPages.count - 1))
                    }
                ),
                in: 0...maxIndex,
                step: 1
            )
            .frame(maxWidth: 260)

            let chars = ReaderPaginator.characterCount(in: content)
            let mins = ReaderPaginator.estimatedReadingMinutes(charCount: chars)
            Text("\(chars) 字 · 约 \(mins) 分钟")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 6)
        .opacity(0.92)
    }

    private func focusModeFloatingBar(content: ChapterContent) -> some View {
        HStack(spacing: 10) {
            Button {
                turnBackward()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.glass)

            Text("\(content.chapter.title) · \(currentPageIndex + 1)/\(max(1, paginatedPages.count))")
                .font(.caption)
                .lineLimit(1)

            Button {
                turnForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.glass)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    vm.isFocusReadingMode = false
                }
            } label: {
                Label("退出沉浸", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 14)
    }

    // MARK: - Empty State

    private var emptyReaderState: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.pages")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("沉浸式仿真阅读器")
                .font(.title3.weight(.semibold))
            Text("支持仿真拖拽翻页、双页对开、系统默认/自定义字体、简繁切换、书签与语音朗读。")
                .foregroundStyle(.secondary)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if vm.bookDetail != nil {
                        Button("开始 / 继续阅读") {
                            vm.openLastReadOrFirstChapter()
                        }
                        .buttonStyle(.glassProminent)

                        Button("展开章节目录") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showTOCSidebar = true
                            }
                        }
                        .buttonStyle(.glass)
                    } else {
                        Button("前往目录与选章") {
                            vm.selectedSection = .catalog
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(vm.readerTheme.backgroundColor.opacity(0.4))
    }

    // MARK: - Toolbar

    private var readerToolbar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showTOCSidebar.toggle()
                    }
                } label: {
                    Label("目录", systemImage: "sidebar.left")
                }
                .buttonStyle(.glass)

                VStack(alignment: .leading, spacing: 1) {
                    Text(vm.previewChapter?.chapter.title ?? (vm.bookDetail?.title ?? "章节阅读器"))
                        .font(.headline)
                        .lineLimit(1)
                    if let prog = vm.readerProgressInfo() {
                        if vm.readerPageMode != .scroll && !paginatedPages.isEmpty {
                            Text("第 \(prog.current)/\(prog.total) 章 · 第 \(currentPageIndex + 1)/\(paginatedPages.count) 页")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("第 \(prog.current) / \(prog.total) 章")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Page turn mode segmented control (仿真翻页 / 平移翻页 / 上下滚动)
                GlassSegmentedControl(selection: $vm.readerPageMode, items: ReaderPageMode.allCases)
                    .frame(width: 214)

                // TTS Speech button
                Button {
                    vm.toggleSpeechForCurrentChapter()
                } label: {
                    Image(systemName: vm.isSpeakingChapter ? "stop.circle.fill" : "speaker.wave.2")
                        .foregroundStyle(vm.isSpeakingChapter ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.glass)
                .disabled(vm.previewChapter == nil)
                .help(vm.isSpeakingChapter ? "停止语音朗读" : "开始本地语音听书")

                // Bookmark current page button
                if let chap = vm.previewChapter?.chapter {
                    let curPage = paginatedPages.indices.contains(currentPageIndex) ? paginatedPages[currentPageIndex] : nil
                    let isMarked = vm.isReaderPageBookmarked(chapterId: chap.id, pageIndex: curPage?.id ?? 0)
                    Button {
                        vm.toggleReaderBookmark(
                            chapter: chap,
                            pageIndex: curPage?.id ?? 0,
                            progressRatio: curPage?.progressRatio ?? 0,
                            excerpt: curPage?.excerpt ?? chap.title
                        )
                    } label: {
                        Image(systemName: isMarked ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isMarked ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.glass)
                    .help("添加/移除页内书签")
                }

                // Compact color-swatch theme selector
                HStack(spacing: 6) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Button {
                            vm.readerTheme = theme
                        } label: {
                            Circle()
                                .fill(theme.swatchColor)
                                .frame(width: 17, height: 17)
                                .overlay {
                                    Circle()
                                        .strokeBorder(
                                            vm.readerTheme == theme ? Color.accentColor : Color.secondary.opacity(0.4),
                                            lineWidth: vm.readerTheme == theme ? 2.5 : 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .help(theme.rawValue)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .capsule)

                Button {
                    showTypographyPopover.toggle()
                } label: {
                    Label("Aa", systemImage: "textformat")
                }
                .buttonStyle(.glass)
                .popover(isPresented: $showTypographyPopover, arrowEdge: .bottom) {
                    typographySettingsPopover
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        vm.isFocusReadingMode = true
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.glass)
                .disabled(vm.previewChapter == nil)
                .help("沉浸专注阅读（隐藏工具栏，点击页面或 Esc 恢复）")

                chapterNavigationButtons
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Typography & Simulation Settings Popover

    private var typographySettingsPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("字体与仿真阅读设置")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("字体选择（默认系统字体）")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(ReaderFontFamily.allCases) { f in
                            let selected = vm.readerFontFamily == f
                            Button {
                                vm.readerFontFamily = f
                            } label: {
                                Text(f.displayName)
                                    .font(.caption.weight(selected ? .semibold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(
                                selected ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }

                    if vm.readerFontFamily == .custom {
                        Picker("系统字体族", selection: $vm.readerCustomFontName) {
                            ForEach(vm.availableSystemFontFamilies, id: \.self) { fam in
                                Text(fam).tag(fam)
                            }
                        }
                        .controlSize(.small)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("简繁显示转换")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $vm.readerScriptMode) {
                        ForEach(ReaderScriptMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("字号")
                        Spacer()
                        Text("\(Int(vm.readerFontSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $vm.readerFontSize, in: 13...28, step: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("行间距")
                        Spacer()
                        Text("\(Int(vm.readerLineSpacing)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $vm.readerLineSpacing, in: 4...20, step: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("段间距")
                        Spacer()
                        Text("\(Int(vm.readerParagraphSpacing)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $vm.readerParagraphSpacing, in: 4...24, step: 2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("左右留白（Padding）")
                        Spacer()
                        Text("\(Int(vm.readerEdgePadding)) px").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $vm.readerEdgePadding, in: 12...96, step: 4)
                }

                Toggle("段首空两格缩进", isOn: $vm.readerIndentEnabled)
                Toggle("宽屏双页对开（仿实体书）", isOn: $vm.readerDualPageEnabled)
                    .disabled(vm.readerPageMode == .scroll)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("自动定时翻页（翻页模式）", isOn: $autoTurnEnabled)
                        .disabled(vm.readerPageMode == .scroll)
                    if autoTurnEnabled {
                        HStack {
                            Text("翻页间隔：\(Int(autoTurnIntervalSeconds)) 秒")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $autoTurnIntervalSeconds, in: 5...45, step: 1)
                        }
                    }

                    HStack {
                        Text("语音朗读语速")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2fx", Double(vm.readerSpeechRate) * 2.0))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(vm.readerSpeechRate) },
                        set: { vm.readerSpeechRate = Float($0) }
                    ), in: 0.35...0.70, step: 0.05)
                }
            }
            .padding(16)
        }
        .frame(width: 310)
        .frame(maxHeight: 520)
    }

    private var chapterNavigationButtons: some View {
        HStack(spacing: 4) {
            Button {
                if let prev = vm.adjacentChapter(offset: -1) {
                    vm.openChapterInReader(prev)
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.glass)
            .disabled(vm.adjacentChapter(offset: -1) == nil)
            .help("上一章")

            Button {
                if let next = vm.adjacentChapter(offset: 1) {
                    vm.openChapterInReader(next)
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.glass)
            .disabled(vm.adjacentChapter(offset: 1) == nil)
            .help("下一章")
        }
    }

    // MARK: - Left Sidebar Drawer (TOC / Bookmarks / Search)

    private var leftSidebarDrawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $sidebarTab) {
                ForEach(ReaderSidebarTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(10)
            .background(.bar)

            Divider()

            switch sidebarTab {
            case .toc:
                if let book = vm.bookDetail {
                    tocList(book)
                } else {
                    Text("尚未加载书籍目录")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .bookmarks:
                bookmarksList
            case .search:
                chapterSearchList
            }
        }
    }

    private func tocList(_ book: BookDetail) -> some View {
        List {
            ForEach(book.volumes) { vol in
                Section(vol.title) {
                    ForEach(vol.chapters) { chap in
                        let isCurrent = vm.previewChapter?.chapter.id == chap.id
                        Button {
                            vm.openChapterInReader(chap)
                        } label: {
                            HStack {
                                Text(chap.title)
                                    .font(.callout)
                                    .foregroundStyle(isCurrent ? Color.accentColor : (chap.isIllustrationChapter ? .purple : .primary))
                                    .fontWeight(isCurrent ? .semibold : .regular)
                                    .lineLimit(1)
                                Spacer()
                                if isCurrent {
                                    Image(systemName: "book.pages.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var bookmarksList: some View {
        let notes = vm.readerBookmarksForCurrentBook()
        return Group {
            if notes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("暂无页内书签")
                        .font(.callout)
                    Text("阅读时点击页面右上角或工具栏书签图标即可收藏位置。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(notes) { note in
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                if let targetChap = vm.bookDetail?.volumes.flatMap(\.chapters).first(where: { $0.id == note.chapterId }) {
                                    if vm.previewChapter?.chapter.id == note.chapterId {
                                        currentPageIndex = min(max(0, note.pageIndex), max(0, paginatedPages.count - 1))
                                    } else {
                                        vm.lastReadPageRatioByChapter[note.chapterId] = note.progressRatio
                                        vm.openChapterInReader(targetChap)
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(note.chapterTitle) · 第 \(note.pageIndex + 1) 页")
                                        .font(.caption.weight(.semibold))
                                    Text(note.excerpt)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                vm.removeReaderBookmark(id: note.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var chapterSearchList: some View {
        VStack(spacing: 8) {
            GlassInputField(
                icon: "magnifyingglass",
                placeholder: "在本章正文中查找关键词...",
                text: $searchInChapterQuery,
                onSubmit: { refreshSearchHits() }
            )
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .onChange(of: searchInChapterQuery) { _, _ in
                refreshSearchHits()
            }

            if searchInChapterQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("输入关键词可搜索本章并直接跳转到对应页码")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else if searchHits.isEmpty {
                Text("未找到匹配内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List(searchHits) { hit in
                    Button {
                        if vm.readerPageMode == .scroll {
                            vm.readerPageMode = .curl
                        }
                        var idx = hit.pageIndex
                        if isDualSpreadActive {
                            idx = (idx / 2) * 2
                        }
                        currentPageIndex = min(max(0, idx), max(0, paginatedPages.count - 1))
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("第 \(hit.pageIndex + 1) 页")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text("...\(hit.snippet)...")
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
    }
}

private struct ReaderImageLightboxView: View {
    let imageURLs: [String]
    let imagesMap: [String: NSImage]
    @Binding var currentIndex: Int
    let onClose: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero

    private var safeIndex: Int {
        min(max(0, currentIndex), max(0, imageURLs.count - 1))
    }

    private var currentImage: NSImage? {
        guard safeIndex < imageURLs.count else { return nil }
        return imagesMap[imageURLs[safeIndex]]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            if let img = currentImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        DragGesture()
                            .onChanged { val in
                                offset = CGSize(
                                    width: dragStartOffset.width + val.translation.width,
                                    height: dragStartOffset.height + val.translation.height
                                )
                            }
                            .onEnded { _ in
                                dragStartOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.25)) {
                            if scale > 1.01 {
                                scale = 1.0
                                offset = .zero
                                dragStartOffset = .zero
                            } else {
                                scale = 2.0
                            }
                        }
                    }
                    .padding(24)
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    Text("插图预览 \(safeIndex + 1) / \(imageURLs.count)")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)

                    Spacer()

                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                withAnimation { scale = max(1.0, scale - 0.5) }
                                if scale <= 1.01 {
                                    offset = .zero
                                    dragStartOffset = .zero
                                }
                            } label: {
                                Image(systemName: "minus.magnifyingglass")
                            }
                            .buttonStyle(.glass)
                            .disabled(scale <= 1.0)

                            Button("\(Int(scale * 100))%") {
                                withAnimation {
                                    scale = 1.0
                                    offset = .zero
                                    dragStartOffset = .zero
                                }
                            }
                            .buttonStyle(.glass)

                            Button {
                                withAnimation { scale = min(4.0, scale + 0.5) }
                            } label: {
                                Image(systemName: "plus.magnifyingglass")
                            }
                            .buttonStyle(.glass)
                            .disabled(scale >= 4.0)

                            if let img = currentImage {
                                Button {
                                    saveImageToDisk(img)
                                } label: {
                                    Label("保存", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.glass)
                            }

                            Button("关闭", action: onClose)
                                .buttonStyle(.glassProminent)
                                .keyboardShortcut(.escape, modifiers: [])
                        }
                    }
                }
                .padding(16)

                Spacer()

                if imageURLs.count > 1 {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 14) {
                            Button {
                                switchTo(safeIndex - 1)
                            } label: {
                                Label("上一张", systemImage: "chevron.left")
                            }
                            .buttonStyle(.glass)
                            .keyboardShortcut(.leftArrow, modifiers: [])
                            .disabled(safeIndex <= 0)

                            Button {
                                switchTo(safeIndex + 1)
                            } label: {
                                Label("下一张", systemImage: "chevron.right")
                            }
                            .buttonStyle(.glass)
                            .keyboardShortcut(.rightArrow, modifiers: [])
                            .disabled(safeIndex >= imageURLs.count - 1)
                        }
                        .padding(12)
                    }
                }
            }
        }
        .frame(minWidth: 860, minHeight: 620)
    }

    private func switchTo(_ idx: Int) {
        guard idx >= 0 && idx < imageURLs.count else { return }
        currentIndex = idx
        scale = 1.0
        offset = .zero
        dragStartOffset = .zero
    }

    private func saveImageToDisk(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.nameFieldStringValue = "illustration_\(safeIndex + 1).jpg"
        if panel.runModal() == .OK, let url = panel.url,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: url.pathExtension.lowercased() == "png" ? .png : .jpeg, properties: [:]) {
            try? data.write(to: url)
        }
    }
}
