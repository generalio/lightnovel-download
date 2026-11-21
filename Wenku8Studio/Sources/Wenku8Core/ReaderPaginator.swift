import AppKit
import Foundation

public enum ReaderPageContent: Hashable, Sendable {
    case text(chapterHeading: String?, paragraphs: [String], startCharOffset: Int, endCharOffset: Int)
    case illustration(imageURL: String, caption: String, imageIndex: Int)
}

public struct ReaderPage: Identifiable, Hashable, Sendable {
    public let id: Int
    public let content: ReaderPageContent
    public let progressRatio: Double

    public init(id: Int, content: ReaderPageContent, progressRatio: Double) {
        self.id = id
        self.content = content
        self.progressRatio = progressRatio
    }

    public var excerpt: String {
        switch content {
        case .text(let heading, let paragraphs, _, _):
            let joined = paragraphs.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let base = joined.isEmpty ? (heading ?? "") : joined
            return String(base.prefix(64))
        case .illustration(_, let caption, _):
            return caption
        }
    }
}

public struct ReaderPaginationConfig: Hashable, Sendable {
    public let fontFamily: ReaderFontFamily
    public let customFontName: String
    public let fontSize: CGFloat
    public let lineSpacing: CGFloat
    public let paragraphSpacing: CGFloat
    public let indentEnabled: Bool
    public let scriptMode: ReaderScriptMode

    public init(
        fontFamily: ReaderFontFamily,
        customFontName: String = "",
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        indentEnabled: Bool,
        scriptMode: ReaderScriptMode
    ) {
        self.fontFamily = fontFamily
        self.customFontName = customFontName
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.indentEnabled = indentEnabled
        self.scriptMode = scriptMode
    }
}

public struct ReaderSearchHit: Identifiable, Hashable, Sendable {
    public let id: String
    public let pageIndex: Int
    public let snippet: String

    public init(id: String, pageIndex: Int, snippet: String) {
        self.id = id
        self.pageIndex = pageIndex
        self.snippet = snippet
    }
}

public enum ReaderPaginator {
    public static func convertScript(_ text: String, mode: ReaderScriptMode) -> String {
        switch mode {
        case .original:
            return text
        case .simplified:
            return text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
        case .traditional:
            return text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
        }
    }

    public static func resolveNSFont(
        family: ReaderFontFamily,
        customFontName: String = "",
        size: CGFloat,
        bold: Bool = false
    ) -> NSFont {
        let weight: NSFont.Weight = bold ? .bold : .regular
        let traits: NSFontTraitMask = bold ? .boldFontMask : []

        switch family {
        case .systemDefault:
            return NSFont.systemFont(ofSize: size, weight: weight)
        case .custom:
            let trimmed = customFontName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let direct = NSFontManager.shared.font(withFamily: trimmed, traits: traits, weight: bold ? 9 : 5, size: size) {
                    return direct
                }
                if let named = NSFont(name: trimmed, size: size) {
                    return named
                }
            }
            return NSFont.systemFont(ofSize: size, weight: weight)
        case .pingfang, .songti, .kaiti, .yuanti:
            let candidates: [String] = {
                switch family {
                case .yuanti: return ["Yuanti SC", "STYuanti-SC-Regular", "PingFang SC"]
                default: return [family.rawValue]
                }
            }()
            for name in candidates {
                if let famFont = NSFontManager.shared.font(withFamily: name, traits: traits, weight: bold ? 9 : 5, size: size) {
                    return famFont
                }
                if let named = NSFont(name: name, size: size) {
                    return named
                }
            }
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
    }

    public static func characterCount(in content: ChapterContent) -> Int {
        content.tokens.reduce(0) { acc, token in
            if case .paragraph(let txt) = token {
                return acc + txt.count
            }
            return acc
        }
    }

    public static func estimatedReadingMinutes(charCount: Int, charsPerMinute: Int = 520) -> Int {
        max(1, Int(ceil(Double(max(1, charCount)) / Double(max(200, charsPerMinute)))))
    }

    public static func plainTextForSpeech(content: ChapterContent, scriptMode: ReaderScriptMode) -> String {
        var lines: [String] = [convertScript(content.chapter.title, mode: scriptMode)]
        for token in content.tokens {
            if case .paragraph(let txt) = token {
                let converted = convertScript(txt, mode: scriptMode).trimmingCharacters(in: .whitespacesAndNewlines)
                if !converted.isEmpty {
                    lines.append(converted)
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func search(_ query: String, in pages: [ReaderPage]) -> [ReaderSearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var hits: [ReaderSearchHit] = []
        for page in pages {
            if case .text(let heading, let paragraphs, _, _) = page.content {
                let allText = ([heading].compactMap { $0 } + paragraphs).joined(separator: " ")
                if let range = allText.range(of: needle, options: .caseInsensitive) {
                    let lower = allText.index(range.lowerBound, offsetBy: -18, limitedBy: allText.startIndex) ?? allText.startIndex
                    let upper = allText.index(range.upperBound, offsetBy: 34, limitedBy: allText.endIndex) ?? allText.endIndex
                    let snippet = String(allText[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
                    hits.append(ReaderSearchHit(id: "\(page.id)_\(hits.count)", pageIndex: page.id, snippet: snippet))
                }
            }
        }
        return hits
    }

    public static func paginate(
        content: ChapterContent,
        config: ReaderPaginationConfig,
        containerSize: CGSize
    ) -> [ReaderPage] {
        let safeWidth = max(240, containerSize.width)
        let safeHeight = max(220, containerSize.height)

        let bodyFont = resolveNSFont(
            family: config.fontFamily,
            customFontName: config.customFontName,
            size: config.fontSize,
            bold: false
        )
        let titleFont = resolveNSFont(
            family: config.fontFamily,
            customFontName: config.customFontName,
            size: config.fontSize + 7,
            bold: true
        )

        let convertedTitle = convertScript(content.chapter.title, mode: config.scriptMode)
        var rawPages: [ReaderPageContent] = []
        var bufferedParagraphs: [String] = []
        var includeTitleInRun = true
        var currentCharOffset = 0
        var imageCounter = 0

        func flushBufferedText() {
            guard !bufferedParagraphs.isEmpty || includeTitleInRun else { return }
            let pagesForRun = layoutTextRun(
                heading: includeTitleInRun ? convertedTitle : nil,
                paragraphs: bufferedParagraphs,
                startCharOffset: currentCharOffset,
                bodyFont: bodyFont,
                titleFont: titleFont,
                lineSpacing: config.lineSpacing,
                paragraphSpacing: config.paragraphSpacing,
                containerSize: CGSize(width: safeWidth, height: safeHeight)
            )
            rawPages.append(contentsOf: pagesForRun)
            for p in bufferedParagraphs {
                currentCharOffset += p.count
            }
            bufferedParagraphs.removeAll()
            includeTitleInRun = false
        }

        for token in content.tokens {
            switch token {
            case .paragraph(let rawText):
                let converted = convertScript(rawText, mode: config.scriptMode)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !converted.isEmpty else { continue }
                let formatted = config.indentEnabled ? "　　\(converted)" : converted
                bufferedParagraphs.append(formatted)
            case .image(let url):
                flushBufferedText()
                imageCounter += 1
                let caption = "\(convertedTitle) · 插图 \(imageCounter)"
                rawPages.append(.illustration(imageURL: url, caption: caption, imageIndex: imageCounter - 1))
            }
        }
        flushBufferedText()

        if rawPages.isEmpty {
            rawPages.append(.text(chapterHeading: convertedTitle, paragraphs: [], startCharOffset: 0, endCharOffset: 0))
        }

        let total = max(1, rawPages.count)
        return rawPages.enumerated().map { idx, pageContent in
            let ratio = total == 1 ? 1.0 : Double(idx) / Double(total - 1)
            return ReaderPage(id: idx, content: pageContent, progressRatio: ratio)
        }
    }

    private static func layoutTextRun(
        heading: String?,
        paragraphs: [String],
        startCharOffset: Int,
        bodyFont: NSFont,
        titleFont: NSFont,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        containerSize: CGSize
    ) -> [ReaderPageContent] {
        let storage = NSTextStorage()
        var headingRange: NSRange?

        if let heading, !heading.isEmpty {
            let titleParaStyle = NSMutableParagraphStyle()
            titleParaStyle.lineSpacing = max(4, lineSpacing * 0.7)
            titleParaStyle.paragraphSpacing = max(16, paragraphSpacing + 10)
            let suffix = paragraphs.isEmpty ? "" : "\n"
            let attrTitle = NSAttributedString(
                string: heading + suffix,
                attributes: [
                    .font: titleFont,
                    .paragraphStyle: titleParaStyle,
                ]
            )
            headingRange = NSRange(location: 0, length: attrTitle.length)
            storage.append(attrTitle)
        }

        let bodyParaStyle = NSMutableParagraphStyle()
        bodyParaStyle.lineSpacing = lineSpacing
        bodyParaStyle.paragraphSpacing = paragraphSpacing
        bodyParaStyle.lineBreakMode = .byWordWrapping

        for (idx, p) in paragraphs.enumerated() {
            let line = (idx < paragraphs.count - 1) ? (p + "\n") : p
            let attrPara = NSAttributedString(
                string: line,
                attributes: [
                    .font: bodyFont,
                    .paragraphStyle: bodyParaStyle,
                ]
            )
            storage.append(attrPara)
        }

        guard storage.length > 0 else {
            return []
        }

        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true
        storage.addLayoutManager(layoutManager)

        var results: [ReaderPageContent] = []
        var glyphOffset = 0
        let totalGlyphs = layoutManager.numberOfGlyphs
        let fullNSString = storage.string as NSString

        // Safety guard against pathological tiny containers
        var iterations = 0
        while glyphOffset < totalGlyphs && iterations < 5000 {
            iterations += 1
            let textContainer = NSTextContainer(size: containerSize)
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            guard glyphRange.length > 0 else { break }

            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let isFirstPageWithHeading = (headingRange != nil && charRange.location < (headingRange?.length ?? 0))

            var pageHeading: String? = nil
            var bodySliceStart = charRange.location
            if isFirstPageWithHeading, let hRange = headingRange {
                pageHeading = heading
                bodySliceStart = min(charRange.location + charRange.length, hRange.location + hRange.length)
            }

            let bodyEnd = charRange.location + charRange.length
            let bodyLength = max(0, bodyEnd - bodySliceStart)
            let bodySubString = bodyLength > 0 ? fullNSString.substring(with: NSRange(location: bodySliceStart, length: bodyLength)) : ""
            let pageParagraphs = bodySubString
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: CharacterSet.newlines) }
                .filter { !$0.isEmpty }

            let headingLen = headingRange?.length ?? 0
            let relStart = max(0, bodySliceStart - headingLen)
            let relEnd = max(relStart, bodyEnd - headingLen)

            results.append(.text(
                chapterHeading: pageHeading,
                paragraphs: pageParagraphs,
                startCharOffset: startCharOffset + relStart,
                endCharOffset: startCharOffset + relEnd
            ))

            glyphOffset = glyphRange.location + glyphRange.length
        }

        return results
    }
}
