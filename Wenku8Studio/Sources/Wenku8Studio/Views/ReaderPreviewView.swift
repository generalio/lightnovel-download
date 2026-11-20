import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Wenku8Core

struct ReaderPreviewView: View {
    @EnvironmentObject var vm: StudioViewModel
    @State private var showTOCSidebar = false
    @State private var showTypographyPopover = false
    @State private var lightboxImageIndex: Int? = nil

    var body: some View {
        HStack(spacing: 0) {
            if showTOCSidebar, let book = vm.bookDetail {
                tocSidebar(book)
                    .frame(width: 260)
                Divider()
            }

            VStack(spacing: 0) {
                readerToolbar

                if vm.isLoadingPreview {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在加载章节正文与插图...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(vm.readerTheme.backgroundColor)
                } else if let content = vm.previewChapter {
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: vm.readerParagraphSpacing) {
                                Color.clear
                                    .frame(height: 1)
                                    .id("readerTop")

                                Text(content.chapter.title)
                                    .font(.custom(vm.readerFontFamily.rawValue, size: vm.readerFontSize + 7))
                                    .fontWeight(.bold)
                                    .foregroundStyle(vm.readerTheme.foregroundColor)
                                    .padding(.bottom, 10)

                                ForEach(Array(content.tokens.enumerated()), id: \.offset) { _, token in
                                    switch token {
                                    case .paragraph(let text):
                                        Text(vm.readerIndentEnabled ? "　　\(text)" : text)
                                            .font(.custom(vm.readerFontFamily.rawValue, size: vm.readerFontSize))
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
                            .frame(maxWidth: vm.readerColumnWidth)
                            .padding(.horizontal, 36)
                            .padding(.vertical, 28)
                            .frame(maxWidth: .infinity)
                        }
                        .background(vm.readerTheme.backgroundColor)
                        .onChange(of: content.chapter.id) { _, _ in
                            scrollProxy.scrollTo("readerTop", anchor: .top)
                        }
                    }
                } else {
                    emptyReaderState
                }
            }
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

    private var emptyReaderState: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.pages")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("沉浸式在线阅读器")
                .font(.title3.weight(.semibold))
            Text("可从左上角打开「目录」挑选章节，或直接继续阅读当前书籍。")
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

    private var readerToolbar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showTOCSidebar.toggle()
                    }
                } label: {
                    Label("目录", systemImage: "sidebar.left")
                }
                .buttonStyle(.glass)
                .disabled(vm.bookDetail == nil)

                VStack(alignment: .leading, spacing: 1) {
                    Text(vm.previewChapter?.chapter.title ?? (vm.bookDetail?.title ?? "章节阅读器"))
                        .font(.headline)
                        .lineLimit(1)
                    if let prog = vm.readerProgressInfo() {
                        Text("第 \(prog.current) / \(prog.total) 章")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Compact color-swatch theme selector (no redundant text label)
                HStack(spacing: 6) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Button {
                            vm.readerTheme = theme
                        } label: {
                            Circle()
                                .fill(theme.swatchColor)
                                .frame(width: 18, height: 18)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
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

                chapterNavigationButtons
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var typographySettingsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("阅读排版")
                .font(.headline)

            Picker("", selection: $vm.readerFontFamily) {
                ForEach(ReaderFontFamily.allCases) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

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
                    Text("版心宽度")
                    Spacer()
                    Text("\(Int(vm.readerColumnWidth)) px").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $vm.readerColumnWidth, in: 580...960, step: 20)
            }

            Toggle("段首空两格缩进", isOn: $vm.readerIndentEnabled)
        }
        .padding(16)
        .frame(width: 280)
    }

    private var chapterNavigationButtons: some View {
        HStack(spacing: 6) {
            Button {
                if let prev = vm.adjacentChapter(offset: -1) {
                    vm.openChapterInReader(prev)
                }
            } label: {
                Label("上一章", systemImage: "chevron.left")
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(vm.adjacentChapter(offset: -1) == nil)

            Button {
                if let next = vm.adjacentChapter(offset: 1) {
                    vm.openChapterInReader(next)
                }
            } label: {
                Label("下一章", systemImage: "chevron.right")
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(vm.adjacentChapter(offset: 1) == nil)
        }
    }

    private func tocSidebar(_ book: BookDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("本书目录")
                    .font(.headline)
                Spacer()
                Text("\(book.volumes.count) 卷")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

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
                                        Image(systemName: "speaker.wave.2.fill")
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
