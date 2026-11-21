import AppKit
import CoreImage
import SwiftUI
import Wenku8Core

struct PageTurnSignal: Equatable {
    let id: UUID
    let forward: Bool
}

struct SimulationPageReaderView: View {
    @EnvironmentObject var vm: StudioViewModel

    let content: ChapterContent
    let pages: [ReaderPage]
    @Binding var currentPageIndex: Int
    @Binding var externalTurnSignal: PageTurnSignal?
    let containerSize: CGSize
    let isDualPage: Bool
    let pageMode: ReaderPageMode
    let onOpenLightbox: (Int) -> Void
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onToggleFocus: () -> Void

    @State private var activeDirection: TurnDirection = .none
    @State private var curlProgress: CGFloat = 0.0
    @State private var dragStartNormY: CGFloat = 0.78
    @State private var dragDeltaNormY: CGFloat = 0.0
    @State private var isAnimatingFlip: Bool = false
    @State private var hoverSide: HoverSide = .none
    @State private var cornerHoverLift: CGFloat = 0.0

    @State private var curlSnapshots: CurlSnapshotPair?

    private enum TurnDirection {
        case none, forward, backward
    }

    private enum HoverSide {
        case none, left, right
    }

    private var step: Int {
        isDualPage ? 2 : 1
    }

    private var safeIndex: Int {
        guard !pages.isEmpty else { return 0 }
        let clamped = min(max(0, currentPageIndex), pages.count - 1)
        if isDualPage {
            return (clamped / 2) * 2
        }
        return clamped
    }

    private var hasPreviousPage: Bool {
        safeIndex > 0
    }

    private var hasNextPage: Bool {
        safeIndex + step < pages.count
    }

    var body: some View {
        let edgePad = CGFloat(vm.readerEdgePadding)
        let sheetWidth = max(360, containerSize.width - edgePad * 2)
        let sheetHeight = max(280, containerSize.height - 20)
        let sheetSize = CGSize(width: sheetWidth, height: sheetHeight)

        ZStack {
            vm.readerTheme.backgroundColor
                .ignoresSafeArea()

            if !pages.isEmpty {
                ZStack {
                    if pageMode == .curl {
                        curlStage(sheetSize: sheetSize)
                    } else {
                        slideStage(sheetSize: sheetSize)
                    }
                }
                .frame(width: sheetWidth, height: sheetHeight)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        if loc.x < sheetWidth * 0.16 {
                            hoverSide = .left
                            updateCornerHoverLift(0.0, sheetSize: sheetSize)
                        } else if loc.x > sheetWidth * 0.84 {
                            hoverSide = .right
                            let inCornerZone = loc.x > sheetWidth * 0.87 && loc.y > sheetHeight * 0.76
                            updateCornerHoverLift(inCornerZone && hasNextPage ? 0.075 : 0.0, sheetSize: sheetSize)
                        } else {
                            hoverSide = .none
                            updateCornerHoverLift(0.0, sheetSize: sheetSize)
                        }
                    case .ended:
                        hoverSide = .none
                        updateCornerHoverLift(0.0, sheetSize: sheetSize)
                    }
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            guard !isAnimatingFlip else { return }
                            handleDragChanged(value: value, sheetSize: sheetSize)
                        }
                        .onEnded { value in
                            guard !isAnimatingFlip else { return }
                            handleDragEnded(value: value, sheetSize: sheetSize)
                        }
                )
                .overlay(alignment: .leading) {
                    edgeTurnButton(isNext: false, sheetSize: sheetSize)
                }
                .overlay(alignment: .trailing) {
                    edgeTurnButton(isNext: true, sheetSize: sheetSize)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: externalTurnSignal) { _, signal in
            guard let signal else { return }
            animateTurn(forward: signal.forward, sheetSize: sheetSize)
        }
        .onChange(of: safeIndex) { _, _ in
            curlSnapshots = nil
        }
    }

    private func updateCornerHoverLift(_ target: CGFloat, sheetSize: CGSize) {
        guard activeDirection == .none, !isAnimatingFlip, abs(cornerHoverLift - target) > 0.005 else { return }
        if target > 0 && curlSnapshots == nil {
            prepareSnapshots(direction: .forward, sheetSize: sheetSize)
        }
        withAnimation(.easeOut(duration: 0.18)) {
            cornerHoverLift = target
        }
        if target == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if activeDirection == .none && cornerHoverLift == 0 {
                    curlSnapshots = nil
                }
            }
        }
    }

    // MARK: - Apple CoreImage Bezier Page Curl Stage

    @ViewBuilder
    private func curlStage(sheetSize: CGSize) -> some View {
        let effectiveProgress: CGFloat = (activeDirection == .none) ? cornerHoverLift : curlProgress
        let effectiveDir: TurnDirection = (activeDirection == .none && cornerHoverLift > 0.001) ? .forward : activeDirection
        let effectiveStartY: CGFloat = (activeDirection == .none && cornerHoverLift > 0.001) ? 0.90 : dragStartNormY

        ZStack {
            paperStackBackdrop(sheetSize: sheetSize)

            if effectiveDir != .none, effectiveProgress > 0.001, let pair = curlSnapshots {
                let isBoundaryBounce = (effectiveDir == .forward && !hasNextPage) || (effectiveDir == .backward && !hasPreviousPage)
                if isBoundaryBounce {
                    spreadOrSingleView(startIndex: safeIndex, size: sheetSize)
                } else {
                    let timeParam: CGFloat = (effectiveDir == .forward)
                        ? effectiveProgress
                        : max(0.0, min(1.0, 1.0 - effectiveProgress))

                    CoreImageBezierCurlView(
                        snapshots: pair,
                        progress: timeParam,
                        dragStartNormY: effectiveStartY,
                        dragDeltaNormY: dragDeltaNormY,
                        pageSize: sheetSize
                    )
                    .frame(width: sheetSize.width, height: sheetSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                }
            } else {
                spreadOrSingleView(startIndex: safeIndex, size: sheetSize)
            }
        }
    }

    // MARK: - Slide Stage

    @ViewBuilder
    private func slideStage(sheetSize: CGSize) -> some View {
        let offsetX: CGFloat = {
            switch activeDirection {
            case .forward: return -curlProgress * sheetSize.width
            case .backward: return curlProgress * sheetSize.width
            case .none: return 0
            }
        }()

        ZStack {
            paperStackBackdrop(sheetSize: sheetSize)

            if activeDirection == .forward {
                if hasNextPage {
                    spreadOrSingleView(startIndex: safeIndex + step, size: sheetSize)
                        .offset(x: sheetSize.width + offsetX)
                } else {
                    boundaryHintSheet(isNext: true, size: sheetSize)
                        .offset(x: sheetSize.width + offsetX)
                }
            } else if activeDirection == .backward {
                if hasPreviousPage {
                    spreadOrSingleView(startIndex: max(0, safeIndex - step), size: sheetSize)
                        .offset(x: -sheetSize.width + offsetX)
                } else {
                    boundaryHintSheet(isNext: false, size: sheetSize)
                        .offset(x: -sheetSize.width + offsetX)
                }
            }

            spreadOrSingleView(startIndex: safeIndex, size: sheetSize)
                .offset(x: offsetX)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Paper & Spread Rendering

    private func paperStackBackdrop(sheetSize: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(vm.readerTheme.backgroundColor.opacity(0.84))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(vm.readerTheme.foregroundColor.opacity(0.10), lineWidth: 1)
                }
                .offset(x: 4, y: 4)

            RoundedRectangle(cornerRadius: 12)
                .fill(vm.readerTheme.backgroundColor.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(vm.readerTheme.foregroundColor.opacity(0.10), lineWidth: 1)
                }
                .offset(x: 2, y: 2)
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
    }

    @ViewBuilder
    private func spreadOrSingleView(startIndex: Int, size: CGSize) -> some View {
        if isDualPage {
            let halfWidth = (size.width - 2) / 2
            HStack(spacing: 0) {
                pageLeaf(index: startIndex, width: halfWidth, height: size.height, showLeftFooter: true, showRightFooter: false)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                vm.readerTheme.foregroundColor.opacity(0.03),
                                vm.readerTheme.foregroundColor.opacity(0.15),
                                vm.readerTheme.foregroundColor.opacity(0.03),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 2)

                if startIndex + 1 < pages.count {
                    pageLeaf(index: startIndex + 1, width: halfWidth, height: size.height, showLeftFooter: false, showRightFooter: true)
                } else {
                    emptyTrailingSpreadLeaf(width: halfWidth, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)
            .background(vm.readerTheme.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(vm.readerTheme.foregroundColor.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        } else {
            pageLeaf(index: startIndex, width: size.width, height: size.height, showLeftFooter: true, showRightFooter: true)
                .frame(width: size.width, height: size.height)
                .background(vm.readerTheme.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(vm.readerTheme.foregroundColor.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }

    private func pageLeaf(
        index: Int,
        width: CGFloat,
        height: CGFloat,
        showLeftFooter: Bool,
        showRightFooter: Bool
    ) -> some View {
        let page = pages[min(max(0, index), pages.count - 1)]
        let bookmarked = vm.isReaderPageBookmarked(chapterId: content.chapter.id, pageIndex: page.id)
        let innerHorizontalPad: CGFloat = isDualPage ? 30 : 40

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(ReaderPaginator.convertScript(content.chapter.title, mode: vm.readerScriptMode))
                    .font(.caption2)
                    .foregroundStyle(vm.readerTheme.foregroundColor.opacity(0.48))
                    .lineLimit(1)

                Spacer()

                if case .text(_, let paras, _, _) = page.content, !paras.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(paras.joined(separator: "\n"), forType: .string)
                        vm.statusBanner = "已复制第 \(page.id + 1) 页正文"
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(vm.readerTheme.foregroundColor.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .help("复制本页正文")
                }

                Button {
                    vm.toggleReaderBookmark(
                        chapter: content.chapter,
                        pageIndex: page.id,
                        progressRatio: page.progressRatio,
                        excerpt: page.excerpt
                    )
                } label: {
                    Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                        .font(.caption)
                        .foregroundStyle(bookmarked ? Color.accentColor : vm.readerTheme.foregroundColor.opacity(0.35))
                }
                .buttonStyle(.plain)
                .help(bookmarked ? "移除此页书签" : "收藏此页书签")
            }
            .padding(.horizontal, innerHorizontalPad)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Group {
                switch page.content {
                case .text(let heading, let paragraphs, _, _):
                    VStack(alignment: .leading, spacing: vm.readerParagraphSpacing) {
                        if let heading, !heading.isEmpty {
                            Text(heading)
                                .font(vm.readerFontFamily.swiftUIFont(
                                    customFontName: vm.readerCustomFontName,
                                    size: vm.readerFontSize + 7,
                                    bold: true
                                ))
                                .lineSpacing(max(4, vm.readerLineSpacing * 0.7))
                                .foregroundStyle(vm.readerTheme.foregroundColor)
                                .padding(.bottom, 10)
                        }

                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                            Text(para)
                                .font(vm.readerFontFamily.swiftUIFont(
                                    customFontName: vm.readerCustomFontName,
                                    size: vm.readerFontSize,
                                    bold: false
                                ))
                                .lineSpacing(vm.readerLineSpacing)
                                .foregroundStyle(vm.readerTheme.foregroundColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, innerHorizontalPad)
                    .padding(.vertical, 6)
                case .illustration(let url, let caption, let imgIdx):
                    VStack(spacing: 12) {
                        Spacer(minLength: 0)
                        if let img = vm.previewImages[url] {
                            Button {
                                onOpenLightbox(imgIdx)
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: width - innerHorizontalPad * 2, maxHeight: height - 130)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption.weight(.semibold))
                                        .padding(7)
                                        .glassEffect(.regular, in: .circle)
                                        .padding(10)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("点击查看大图预览")
                        } else {
                            ProgressView()
                        }
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(vm.readerTheme.foregroundColor.opacity(0.55))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleFocus()
            }

            HStack {
                if showLeftFooter {
                    Text("\(Int(round(page.progressRatio * 100)))% · \(Date.now.formatted(date: .omitted, time: .shortened))")
                }
                Spacer()
                if showRightFooter {
                    Text("第 \(page.id + 1) / \(pages.count) 页")
                        .monospacedDigit()
                }
            }
            .font(.caption2)
            .foregroundStyle(vm.readerTheme.foregroundColor.opacity(0.45))
            .padding(.horizontal, innerHorizontalPad)
            .padding(.bottom, 14)
            .padding(.top, 8)
        }
        .frame(width: width, height: height)
    }

    private func emptyTrailingSpreadLeaf(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.title2)
                .foregroundStyle(vm.readerTheme.foregroundColor.opacity(0.3))
            Text("本章已读完")
                .font(.callout)
                .foregroundStyle(vm.readerTheme.foregroundColor.opacity(0.5))
            if vm.adjacentChapter(offset: 1) != nil {
                Button("进入下一章") {
                    onNextChapter()
                }
                .buttonStyle(.glass)
            }
            Spacer()
        }
        .frame(width: width, height: height)
    }

    private func boundaryHintSheet(isNext: Bool, size: CGSize) -> some View {
        VStack(spacing: 10) {
            Image(systemName: isNext ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text(isNext ? "松开进入下一章" : "松开返回上一章")
                .font(.headline)
                .foregroundStyle(vm.readerTheme.foregroundColor)
        }
        .frame(width: size.width, height: size.height)
        .background(vm.readerTheme.backgroundColor, in: RoundedRectangle(cornerRadius: 12))
    }

    private func edgeTurnButton(isNext: Bool, sheetSize: CGSize) -> some View {
        let canTurnChapter = isNext ? (vm.adjacentChapter(offset: 1) != nil) : (vm.adjacentChapter(offset: -1) != nil)
        let canTurnPage = isNext ? hasNextPage : hasPreviousPage
        let isVisible = (isNext && hoverSide == .right) || (!isNext && hoverSide == .left)

        return Button {
            animateTurn(forward: isNext, sheetSize: sheetSize)
        } label: {
            Image(systemName: isNext ? "chevron.right" : "chevron.left")
                .font(.title3.weight(.semibold))
                .foregroundStyle(vm.readerTheme.foregroundColor.opacity(0.75))
                .frame(width: 36, height: 54)
                .glassEffect(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isVisible && (canTurnPage || canTurnChapter) ? 0.92 : 0.0)
        .padding(isNext ? .trailing : .leading, 10)
        .animation(.easeInOut(duration: 0.15), value: isVisible)
        .help(isNext ? (hasNextPage ? "下一页 (→ / Space)" : "下一章") : (hasPreviousPage ? "上一页 (←)" : "上一章"))
    }

    // MARK: - Snapshot Capture for GPU CoreImage Curl

    @MainActor
    private func prepareSnapshots(direction: TurnDirection, sheetSize: CGSize) {
        guard pageMode == .curl else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        func snapshotCIImage(for view: some View) -> CIImage? {
            let renderer = ImageRenderer(content: view.environmentObject(vm))
            renderer.scale = scale
            renderer.proposedSize = ProposedViewSize(sheetSize)
            guard let cgImg = renderer.cgImage else { return nil }
            return CIImage(cgImage: cgImg)
        }

        let currentView = spreadOrSingleView(startIndex: safeIndex, size: sheetSize)
        guard let currentCI = snapshotCIImage(for: currentView) else { return }

        let frontCI: CIImage
        let targetCI: CIImage

        if direction == .forward {
            guard hasNextPage else { return }
            let nextView = spreadOrSingleView(startIndex: safeIndex + step, size: sheetSize)
            guard let nextCI = snapshotCIImage(for: nextView) else { return }
            frontCI = currentCI
            targetCI = nextCI
        } else {
            guard hasPreviousPage else { return }
            let prevView = spreadOrSingleView(startIndex: max(0, safeIndex - step), size: sheetSize)
            guard let prevCI = snapshotCIImage(for: prevView) else { return }
            frontCI = prevCI
            targetCI = currentCI
        }

        let extent = frontCI.extent
        let backingNSColor = NSColor(vm.readerTheme.paperBackingColor).usingColorSpace(.sRGB) ?? NSColor.white
        let paperCI = CIImage(color: CIColor(color: backingNSColor) ?? CIColor.white).cropped(to: extent)

        // Blend faint 16% ink bleed-through over warm paper color for the curled page's backside
        let alphaFilter = CIFilter(name: "CIColorMatrix")
        alphaFilter?.setValue(frontCI, forKey: kCIInputImageKey)
        alphaFilter?.setValue(CIVector(x: 0, y: 0, z: 0, w: 0.15), forKey: "inputAVector")
        let faintFront = alphaFilter?.outputImage ?? frontCI
        let backsideCI = faintFront.composited(over: paperCI).cropped(to: extent)

        curlSnapshots = CurlSnapshotPair(
            front: frontCI,
            target: targetCI,
            backside: backsideCI,
            extent: extent,
            scale: scale
        )
    }

    // MARK: - Drag & Cubic Bezier Turn Mechanics

    private func handleDragChanged(value: DragGesture.Value, sheetSize: CGSize) {
        cornerHoverLift = 0.0
        let dx = value.translation.width
        let span = max(240, sheetSize.width * 0.68)

        dragStartNormY = min(1.0, max(0.0, value.startLocation.y / max(1, sheetSize.height)))
        dragDeltaNormY = min(0.5, max(-0.5, value.translation.height / max(1, sheetSize.height)))

        if dx < 0 {
            if activeDirection != .forward {
                activeDirection = .forward
                prepareSnapshots(direction: .forward, sheetSize: sheetSize)
            }
            let rawP = min(1.0, max(0.0, -dx / span))
            curlProgress = hasNextPage ? rawP : rawP * 0.25
        } else if dx > 0 {
            if activeDirection != .backward {
                activeDirection = .backward
                prepareSnapshots(direction: .backward, sheetSize: sheetSize)
            }
            let rawP = min(1.0, max(0.0, dx / span))
            curlProgress = hasPreviousPage ? rawP : rawP * 0.25
        }
    }

    private func handleDragEnded(value: DragGesture.Value, sheetSize: CGSize) {
        let span = max(240, sheetSize.width * 0.68)
        let predictedProgress = abs(value.predictedEndTranslation.width) / span
        let shouldComplete = curlProgress > 0.20 || predictedProgress > 0.45

        switch activeDirection {
        case .forward:
            if hasNextPage && shouldComplete {
                completeTurn(forward: true)
            } else {
                let goNextChapter = !hasNextPage && curlProgress > 0.14
                cancelTurn {
                    if goNextChapter { onNextChapter() }
                }
            }
        case .backward:
            if hasPreviousPage && shouldComplete {
                completeTurn(forward: false)
            } else {
                let goPrevChapter = !hasPreviousPage && curlProgress > 0.14
                cancelTurn {
                    if goPrevChapter { onPreviousChapter() }
                }
            }
        case .none:
            curlProgress = 0
            curlSnapshots = nil
        }
    }

    private func animateTurn(forward: Bool, sheetSize: CGSize) {
        guard !isAnimatingFlip else { return }
        cornerHoverLift = 0.0
        if forward {
            if hasNextPage {
                prepareSnapshots(direction: .forward, sheetSize: sheetSize)
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    activeDirection = .forward
                    curlProgress = 0.0
                    dragStartNormY = 0.84
                    dragDeltaNormY = -0.10
                }
                completeTurn(forward: true)
            } else {
                onNextChapter()
            }
        } else {
            if hasPreviousPage {
                prepareSnapshots(direction: .backward, sheetSize: sheetSize)
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    activeDirection = .backward
                    curlProgress = 0.0
                    dragStartNormY = 0.84
                    dragDeltaNormY = -0.06
                }
                completeTurn(forward: false)
            } else {
                onPreviousChapter()
            }
        }
    }

    private func completeTurn(forward: Bool) {
        isAnimatingFlip = true
        let duration: Double = 0.42
        withAnimation(.timingCurve(0.22, 0.84, 0.34, 1.0, duration: duration)) {
            curlProgress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                if forward {
                    currentPageIndex = min(pages.count - 1, safeIndex + step)
                } else {
                    currentPageIndex = max(0, safeIndex - step)
                }
                activeDirection = .none
                curlProgress = 0.0
                dragDeltaNormY = 0.0
                curlSnapshots = nil
            }
            isAnimatingFlip = false
        }
    }

    private func cancelTurn(after: (() -> Void)? = nil) {
        isAnimatingFlip = true
        let duration: Double = 0.24
        withAnimation(.spring(response: duration, dampingFraction: 0.86)) {
            curlProgress = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                activeDirection = .none
                curlProgress = 0.0
                dragDeltaNormY = 0.0
                curlSnapshots = nil
            }
            isAnimatingFlip = false
            after?()
        }
    }
}

// MARK: - CoreImage GPU Bezier Page Curl Renderer

private struct CurlSnapshotPair {
    let front: CIImage
    let target: CIImage
    let backside: CIImage
    let extent: CGRect
    let scale: CGFloat
}

private enum CoreImageCurlEngine {
    static let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    static func cubicBezierY(_ t: CGFloat, p1: CGPoint, p2: CGPoint) -> CGFloat {
        let u = 1.0 - t
        let tt = t * t
        let uu = u * u
        return 3.0 * uu * t * p1.y + 3.0 * u * tt * p2.y + tt * t
    }

    static func renderFrame(
        snapshots: CurlSnapshotPair,
        progress: CGFloat,
        dragStartNormY: CGFloat,
        dragDeltaNormY: CGFloat
    ) -> CGImage? {
        guard let filter = CIFilter(name: "CIPageCurlWithShadowTransition") else {
            return nil
        }

        let t = min(1.0, max(0.0, progress))
        // Cubic Bezier progression curve for natural paper stiffness & release
        let bezierTime = cubicBezierY(t, p1: CGPoint(x: 0.24, y: 0.14), p2: CGPoint(x: 0.30, y: 1.0))

        // Cubic Bezier rolling cylinder radius (in pixels): lifts smoothly from corner & relaxes near completion
        let pixelMinDim = min(snapshots.extent.width, snapshots.extent.height)
        let bell = sin(min(1.0, max(0.0, bezierTime)) * CGFloat.pi)
        let radius = max(14.0, pixelMinDim * (0.04 + 0.115 * pow(bell, 0.72)))

        // Corner-aware curl angle:
        // CoreImage angles: pi = pure right-to-left, 3pi/4 (135 deg) = bottom-right corner, -3pi/4 (-135 deg) = top-right corner
        let verticalBias = (dragStartNormY - 0.5) * 0.95 - dragDeltaNormY * 0.65
        let clampedOffset = min(0.62, max(-0.62, verticalBias * (1.0 - pow(bezierTime, 1.4))))
        let angle = CGFloat.pi - clampedOffset

        filter.setValue(snapshots.front, forKey: kCIInputImageKey)
        filter.setValue(snapshots.target, forKey: kCIInputTargetImageKey)
        filter.setValue(snapshots.backside, forKey: "inputBacksideImage")
        filter.setValue(CIVector(cgRect: snapshots.extent), forKey: kCIInputExtentKey)
        filter.setValue(CIVector(cgRect: snapshots.extent), forKey: "inputShadowExtent")
        filter.setValue(bezierTime, forKey: kCIInputTimeKey)
        filter.setValue(angle, forKey: kCIInputAngleKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.setValue(0.45, forKey: "inputShadowSize")
        filter.setValue(0.62, forKey: "inputShadowAmount")

        guard let output = filter.outputImage?.cropped(to: snapshots.extent) else {
            return nil
        }
        return context.createCGImage(output, from: snapshots.extent)
    }
}

private struct CoreImageBezierCurlView: View, Animatable {
    let snapshots: CurlSnapshotPair
    var progress: CGFloat
    var dragStartNormY: CGFloat
    var dragDeltaNormY: CGFloat
    let pageSize: CGSize

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(progress, AnimatablePair(dragStartNormY, dragDeltaNormY)) }
        set {
            progress = newValue.first
            dragStartNormY = newValue.second.first
            dragDeltaNormY = newValue.second.second
        }
    }

    var body: some View {
        if let cgImg = CoreImageCurlEngine.renderFrame(
            snapshots: snapshots,
            progress: progress,
            dragStartNormY: dragStartNormY,
            dragDeltaNormY: dragDeltaNormY
        ) {
            Image(decorative: cgImg, scale: snapshots.scale)
                .resizable()
                .frame(width: pageSize.width, height: pageSize.height)
        } else {
            Color.clear
        }
    }
}
