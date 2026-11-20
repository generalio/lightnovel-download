import Foundation

public struct VolumeBuildInput: Sendable {
    public let volume: VolumeItem
    public let chapters: [ChapterContent]
    public let illustrationChapter: ChapterContent?

    public init(volume: VolumeItem, chapters: [ChapterContent], illustrationChapter: ChapterContent?) {
        self.volume = volume
        self.chapters = chapters
        self.illustrationChapter = illustrationChapter
    }
}

public enum EPUBBuilderError: LocalizedError {
    case zipFailed(String)
    case noChaptersSelected

    public var errorDescription: String? {
        switch self {
        case .zipFailed(let msg): return "EPUB 打包失败：\(msg)"
        case .noChaptersSelected: return "没有可打包的章节"
        }
    }
}

public struct EPUBBuilder {
    private static let creditPrefixes = [
        "台版 ", "网译版", "轻之国度", "天使动漫", "图源：", "图源:",
        "扫图：", "扫图:", "录入：", "录入:", "修图：", "修图:",
        "翻译：", "翻译:", "校对：", "校对:", "润色：", "润色:", "转自 "
    ]

    public init() {}

    public func buildEPUB(
        book: BookDetail,
        volumes: [VolumeBuildInput],
        images: [String: DownloadedImageAsset],
        outputDirectory: URL,
        config: AssemblyConfig
    ) throws -> OutputArtifact {
        guard !volumes.isEmpty else {
            throw EPUBBuilderError.noChaptersSelected
        }

        let isMerged = (config.exportMode == .mergedSingle && volumes.count > 1) || volumes.count > 1
        let primaryVolume = volumes[0].volume
        let effectiveTitle = config.customTitleOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? book.title
            : config.customTitleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveAuthor = config.customAuthorOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (book.author.isEmpty ? "未知" : book.author)
            : config.customAuthorOverride.trimmingCharacters(in: .whitespacesAndNewlines)

        let volumeLabel = isMerged ? "合集(\(volumes.count)卷)" : primaryVolume.title
        let epubTitle = isMerged ? "\(effectiveTitle)（\(volumeLabel)）" : "\(effectiveTitle)-\(primaryVolume.title)"
        let filenameBase = renderFilename(
            template: config.filenameTemplate,
            title: effectiveTitle,
            volume: volumeLabel,
            index: primaryVolume.index,
            author: effectiveAuthor,
            bookId: book.bookId
        )

        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let uuidStr = UUID().uuidString.lowercased()
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("wenku8_epub_\(uuidStr)", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let metaInfDir = tempRoot.appendingPathComponent("META-INF", isDirectory: true)
        let oebpsDir = tempRoot.appendingPathComponent("OEBPS", isDirectory: true)
        let textDir = oebpsDir.appendingPathComponent("Text", isDirectory: true)
        let imagesDir = oebpsDir.appendingPathComponent("Images", isDirectory: true)
        let stylesDir = oebpsDir.appendingPathComponent("Styles", isDirectory: true)

        for dir in [metaInfDir, textDir, imagesDir, stylesDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Write mimetype & container.xml
        try "application/epub+zip".write(
            to: tempRoot.appendingPathComponent("mimetype"),
            atomically: true,
            encoding: .utf8
        )
        try containerXML().write(
            to: metaInfDir.appendingPathComponent("container.xml"),
            atomically: true,
            encoding: .utf8
        )

        // Write shared stylesheet
        try styleCSS(config: config).write(
            to: stylesDir.appendingPathComponent("style.css"),
            atomically: true,
            encoding: .utf8
        )

        // Collect & deduplicate image assets
        var registeredAssets: [String: (id: String, filename: String, mime: String, width: Int, height: Int)] = [:]
        var orderedImageFiles: [(id: String, filename: String, mime: String)] = []

        func registerAsset(_ key: String, asset: DownloadedImageAsset) -> (id: String, filename: String, mime: String, width: Int, height: Int) {
            if let existing = registeredAssets[key] {
                return existing
            }
            let idx = orderedImageFiles.count
            let stem = String(format: "img_%03d", idx)
            let filename = "\(stem)\(asset.fileExtension)"
            let info = (id: stem, filename: filename, mime: asset.mimeType, width: asset.width, height: asset.height)
            registeredAssets[key] = info
            orderedImageFiles.append((id: stem, filename: filename, mime: asset.mimeType))
            try? asset.data.write(to: imagesDir.appendingPathComponent(filename))
            return info
        }

        // Determine cover asset
        var coverInfo: (id: String, filename: String, mime: String, width: Int, height: Int)?
        var usedColorCoverURLs = Set<String>()

        if config.includeCover {
            switch config.coverSource {
            case .customLocalFile:
                if !config.customCoverPath.isEmpty,
                   let data = try? Data(contentsOf: URL(fileURLWithPath: config.customCoverPath)) {
                    let (ext, mime) = Wenku8Client.detectImageFormat(data: data, urlString: config.customCoverPath)
                    let (w, h) = Wenku8Client.measureImageSize(data: data)
                    let localAsset = DownloadedImageAsset(url: "local://cover", data: data, fileExtension: ext, mimeType: mime, width: w, height: h)
                    coverInfo = registerAsset("local://cover", asset: localAsset)
                }
            case .mainPageCover:
                if let mainAsset = images[book.coverURL] {
                    coverInfo = registerAsset(book.coverURL, asset: mainAsset)
                }
            case .autoColorFirst:
                if let firstColorURL = volumes.first?.illustrationChapter?.imageURLs.first,
                   let colorAsset = images[firstColorURL] {
                    coverInfo = registerAsset(firstColorURL, asset: colorAsset)
                    usedColorCoverURLs.insert(firstColorURL)
                } else if let mainAsset = images[book.coverURL] {
                    coverInfo = registerAsset(book.coverURL, asset: mainAsset)
                }
            }
        }

        // Track spine & manifest items
        struct SpineDoc {
            let id: String
            let href: String
            let title: String
        }

        var manifestHTMLDocs: [SpineDoc] = []
        var spineRefs: [String] = []
        var frontNavItems: [(title: String, href: String)] = []
        var backNavItems: [(title: String, href: String)] = []
        var volumeNavGroups: [EPUBNavVolumeGroup] = []

        if config.includeCover {
            let coverHTML = buildCoverXHTML(
                title: epubTitle,
                volumeLabel: volumeLabel,
                coverFilename: coverInfo?.filename,
                width: coverInfo?.width ?? 600,
                height: coverInfo?.height ?? 850
            )
            try coverHTML.write(to: textDir.appendingPathComponent("cover.xhtml"), atomically: true, encoding: .utf8)
            manifestHTMLDocs.append(SpineDoc(id: "cover_xhtml", href: "Text/cover.xhtml", title: "封面"))
            spineRefs.append("cover_xhtml")
            frontNavItems.append(("封面", "Text/cover.xhtml"))
        }

        if config.includeInfoPage {
            let infoHTML = buildInfoXHTML(
                book: book,
                title: effectiveTitle,
                volumeLabel: volumeLabel,
                author: effectiveAuthor,
                coverFilename: coverInfo?.filename
            )
            try infoHTML.write(to: textDir.appendingPathComponent("info.xhtml"), atomically: true, encoding: .utf8)
            manifestHTMLDocs.append(SpineDoc(id: "info_xhtml", href: "Text/info.xhtml", title: "书籍简介"))
            spineRefs.append("info_xhtml")
            frontNavItems.append(("书籍简介", "Text/info.xhtml"))
        }

        // Collect all body inline image URLs for dedup
        var allBodyImageURLs = Set<String>()
        for vInput in volumes {
            for chap in vInput.chapters {
                allBodyImageURLs.formUnion(chap.imageURLs)
            }
        }

        // Build color pages helper
        var colorDocsBefore: [SpineDoc] = []
        var colorDocsAfter: [SpineDoc] = []

        if config.colorLayout != .skipColor {
            var colorFilenames: [String] = []
            for vInput in volumes {
                if let illus = vInput.illustrationChapter {
                    for url in illus.imageURLs {
                        if usedColorCoverURLs.contains(url) && !isMerged {
                            continue
                        }
                        if config.dedupColorImages && allBodyImageURLs.contains(url) {
                            continue
                        }
                        if let asset = images[url] {
                            let info = registerAsset(url, asset: asset)
                            if !colorFilenames.contains(info.filename) {
                                colorFilenames.append(info.filename)
                            }
                        }
                    }
                }
            }

            // Append user-selected custom local color images
            for (idx, localPath) in config.extraColorImagePaths.enumerated() {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: localPath)) {
                    let (ext, mime) = Wenku8Client.detectImageFormat(data: data, urlString: localPath)
                    let (w, h) = Wenku8Client.measureImageSize(data: data)
                    let key = "local://extra_\(idx)_\(localPath)"
                    let localAsset = DownloadedImageAsset(url: key, data: data, fileExtension: ext, mimeType: mime, width: w, height: h)
                    let info = registerAsset(key, asset: localAsset)
                    colorFilenames.append(info.filename)
                }
            }

            if !colorFilenames.isEmpty {
                switch config.colorLayout {
                case .oneImagePerPage:
                    for (idx, fname) in colorFilenames.enumerated() {
                        let docId = String(format: "color_%03d", idx)
                        let fileName = "\(docId).xhtml"
                        let xhtml = buildSingleColorPageXHTML(title: "彩插 \(idx + 1)", imageFilename: fname)
                        try xhtml.write(to: textDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
                        let doc = SpineDoc(id: docId, href: "Text/\(fileName)", title: idx == 0 ? "彩插" : "彩插 \(idx + 1)")
                        if config.colorPlacement == .beforeBody {
                            colorDocsBefore.append(doc)
                        } else {
                            colorDocsAfter.append(doc)
                        }
                    }
                    let targetNav = SpineDoc(id: "color_000", href: "Text/color_000.xhtml", title: "彩插")
                    if config.colorPlacement == .beforeBody {
                        frontNavItems.append((targetNav.title, targetNav.href))
                    } else {
                        backNavItems.append((targetNav.title, targetNav.href))
                    }
                case .singleScrollPage:
                    let xhtml = buildMultiColorPageXHTML(title: "彩插", imageFilenames: colorFilenames)
                    try xhtml.write(to: textDir.appendingPathComponent("color.xhtml"), atomically: true, encoding: .utf8)
                    let doc = SpineDoc(id: "color_xhtml", href: "Text/color.xhtml", title: "彩插")
                    if config.colorPlacement == .beforeBody {
                        colorDocsBefore.append(doc)
                        frontNavItems.append(("彩插", "Text/color.xhtml"))
                    } else {
                        colorDocsAfter.append(doc)
                        backNavItems.append(("彩插", "Text/color.xhtml"))
                    }
                case .skipColor:
                    break
                }
            }
        }

        for doc in colorDocsBefore {
            manifestHTMLDocs.append(doc)
            spineRefs.append(doc.id)
        }

        // Write body chapters
        var chapGlobalIndex = 0
        for vInput in volumes {
            var volNavChapters: [(title: String, href: String)] = []
            for chapContent in vInput.chapters {
                let docId = String(format: "chap_%04d", chapGlobalIndex)
                let fileName = "\(docId).xhtml"
                let href = "Text/\(fileName)"
                chapGlobalIndex += 1

                var bodyImageFilenames: [String: String] = [:]
                for url in chapContent.imageURLs {
                    if let asset = images[url] {
                        let info = registerAsset(url, asset: asset)
                        bodyImageFilenames[url] = info.filename
                    }
                }

                let xhtml = buildChapterXHTML(
                    chapter: chapContent,
                    imageFilenames: bodyImageFilenames,
                    cleanCredits: config.cleanCreditsHeader
                )
                try xhtml.write(to: textDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)

                manifestHTMLDocs.append(SpineDoc(id: docId, href: href, title: chapContent.chapter.title))
                spineRefs.append(docId)
                volNavChapters.append((chapContent.chapter.title, href))
            }

            if let firstHref = volNavChapters.first?.href {
                volumeNavGroups.append(EPUBNavVolumeGroup(
                    volumeTitle: vInput.volume.title,
                    firstHref: firstHref,
                    chapters: volNavChapters
                ))
            }
        }

        for doc in colorDocsAfter {
            manifestHTMLDocs.append(doc)
            spineRefs.append(doc.id)
        }

        // Write toc.ncx (always included for EPUB 2 compatibility)
        let ncxContent = buildNCX(
            title: epubTitle,
            uuid: uuidStr,
            isMerged: isMerged,
            frontItems: frontNavItems,
            volumeGroups: volumeNavGroups,
            backItems: backNavItems
        )
        try ncxContent.write(to: oebpsDir.appendingPathComponent("toc.ncx"), atomically: true, encoding: .utf8)

        // Write EPUB 3 nav.xhtml if EPUB 3 mode
        if config.epubVersion == .epub3 {
            let navXHTML = buildNavXHTML(
                title: epubTitle,
                isMerged: isMerged,
                frontItems: frontNavItems,
                volumeGroups: volumeNavGroups,
                backItems: backNavItems
            )
            try navXHTML.write(to: oebpsDir.appendingPathComponent("nav.xhtml"), atomically: true, encoding: .utf8)
        }

        // Write content.opf
        let opfContent = buildOPF(
            version: config.epubVersion,
            uuid: uuidStr,
            title: epubTitle,
            seriesTitle: effectiveTitle,
            seriesIndex: isMerged ? nil : primaryVolume.index,
            author: effectiveAuthor,
            book: book,
            coverId: coverInfo?.id,
            htmlDocs: manifestHTMLDocs.map { ($0.id, $0.href) },
            imageDocs: orderedImageFiles,
            spineRefs: spineRefs,
            includeCover: config.includeCover
        )
        try opfContent.write(to: oebpsDir.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        // Zip into final EPUB
        let outURL = outputDirectory.appendingPathComponent("\(filenameBase).epub")
        if fm.fileExists(atPath: outURL.path) {
            try fm.removeItem(at: outURL)
        }

        try runZip(args: ["-0", "-X", outURL.path, "mimetype"], cwd: tempRoot)
        try runZip(args: ["-rq", outURL.path, "META-INF", "OEBPS"], cwd: tempRoot)

        let attrs = try fm.attributesOfItem(atPath: outURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        return OutputArtifact(title: epubTitle, filePath: outURL.path, fileSizeBytes: fileSize)
    }

    // MARK: - Helpers & Templates

    public func renderFilename(
        template: String,
        title: String,
        volume: String,
        index: Int,
        author: String,
        bookId: String
    ) -> String {
        let baseTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "{title}-{volume}"
            : template
        let replaced = baseTemplate
            .replacingOccurrences(of: "{title}", with: title)
            .replacingOccurrences(of: "{volume}", with: volume)
            .replacingOccurrences(of: "{index}", with: String(index))
            .replacingOccurrences(of: "{author}", with: author)
            .replacingOccurrences(of: "{id}", with: bookId)
        return Self.sanitizeFilename(replaced)
    }

    public static func sanitizeFilename(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "?*\"<>|:/\\")
        var result = ""
        for scalar in raw.unicodeScalars {
            if illegal.contains(scalar) || scalar.value < 32 {
                result.append("\u{25A0}")
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return trimmed.isEmpty ? "untitled" : trimmed
    }

    public static func xmlEscape(_ str: String) -> String {
        var s = str
        s = s.replacingOccurrences(of: "&", with: "&amp;")
        s = s.replacingOccurrences(of: "<", with: "&lt;")
        s = s.replacingOccurrences(of: ">", with: "&gt;")
        s = s.replacingOccurrences(of: "\"", with: "&quot;")
        s = s.replacingOccurrences(of: "'", with: "&apos;")
        return s
    }

    private func runZip(args: [String], cwd: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.arguments = args
        proc.currentDirectoryURL = cwd
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "zip exit \(proc.terminationStatus)"
            throw EPUBBuilderError.zipFailed(msg)
        }
    }

    private func containerXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>

        """
    }

    private func styleCSS(config: AssemblyConfig) -> String {
        """
        body {
          margin: 1em 1.2em;
          line-height: \(String(format: "%.2f", config.lineHeight));
        }
        h1, h2 {
          text-align: center;
          margin: 1em 0 1.2em 0;
          line-height: 1.4;
        }
        p {
          text-indent: \(String(format: "%.2f", config.textIndentEm))em;
          margin: 0 0 \(String(format: "%.2f", config.paragraphSpacingEm))em 0;
        }
        .illus-box {
          text-align: center;
          margin: 0.8em 0;
          text-indent: 0;
        }
        img {
          max-width: 100%;
          height: auto;
        }
        .color-page {
          text-align: center;
          page-break-after: always;
          break-after: page;
          margin: 0;
        }
        .info-box {
          margin: 1em 0;
          line-height: 1.6;
        }
        .info-box p {
          text-indent: 0;
          margin: 0.35em 0;
        }
        .tag {
          display: inline-block;
          padding: 0.1em 0.45em;
          margin: 0.15em;
          border: 1px solid #888;
          border-radius: 4px;
          font-size: 0.85em;
        }

        """
    }

    private func buildCoverXHTML(title: String, volumeLabel: String, coverFilename: String?, width: Int, height: Int) -> String {
        if let coverFilename {
            let safeCover = Self.xmlEscape(coverFilename)
            return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:xlink="http://www.w3.org/1999/xlink">
            <head>
              <meta charset="utf-8"/>
              <title>Cover</title>
              <style type="text/css">html,body{margin:0;padding:0;height:100%;}</style>
            </head>
            <body>
              <div style="text-align: center; padding: 0; margin: 0; height: 100%;">
                <svg xmlns="http://www.w3.org/2000/svg" height="100%" preserveAspectRatio="xMidYMid meet" version="1.1" viewBox="0 0 \(width) \(height)" width="100%" xmlns:xlink="http://www.w3.org/1999/xlink">
                  <image width="\(width)" height="\(height)" xlink:href="../Images/\(safeCover)"/>
                </svg>
              </div>
            </body>
            </html>
            """
        } else {
            return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
              <meta charset="utf-8"/>
              <title>Cover</title>
            </head>
            <body>
              <div style="text-align:center;margin-top:30%;">
                <h1>\(Self.xmlEscape(title))</h1>
                <p>\(Self.xmlEscape(volumeLabel))</p>
              </div>
            </body>
            </html>
            """
        }
    }

    private func buildInfoXHTML(book: BookDetail, title: String, volumeLabel: String, author: String, coverFilename: String?) -> String {
        var parts: [String] = [
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
              <meta charset="utf-8"/>
              <title>书籍简介</title>
              <link rel="stylesheet" type="text/css" href="../Styles/style.css"/>
            </head>
            <body>
              <h1>\(Self.xmlEscape(title))</h1>
              <h2>\(Self.xmlEscape(volumeLabel))</h2>
            """
        ]
        if let coverFilename {
            parts.append("  <div class=\"illus-box\"><img alt=\"Cover\" src=\"../Images/\(Self.xmlEscape(coverFilename))\" style=\"max-height:280px;\"/></div>")
        }
        parts.append("  <div class=\"info-box\">")
        parts.append("    <p><strong>作者：</strong>\(Self.xmlEscape(author))</p>")
        if !book.publisher.isEmpty {
            parts.append("    <p><strong>文库：</strong>\(Self.xmlEscape(book.publisher))</p>")
        }
        if !book.status.isEmpty {
            parts.append("    <p><strong>状态：</strong>\(Self.xmlEscape(book.status))</p>")
        }
        if !book.lastUpdated.isEmpty {
            parts.append("    <p><strong>更新：</strong>\(Self.xmlEscape(book.lastUpdated))</p>")
        }
        if !book.wordCount.isEmpty {
            parts.append("    <p><strong>字数：</strong>\(Self.xmlEscape(book.wordCount))</p>")
        }
        if !book.tags.isEmpty {
            let tagsHTML = book.tags.map { "<span class=\"tag\">\(Self.xmlEscape($0))</span>" }.joined()
            parts.append("    <p><strong>标签：</strong>\(tagsHTML)</p>")
        }
        parts.append("  </div>")
        if !book.description.isEmpty {
            parts.append("  <hr/>\n  <div class=\"info-box\">\n    <p><strong>内容简介：</strong></p>")
            for line in book.description.components(separatedBy: .newlines) {
                let p = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !p.isEmpty {
                    parts.append("    <p style=\"text-indent:2em;\">\(Self.xmlEscape(p))</p>")
                }
            }
            parts.append("  </div>")
        }
        parts.append("</body>\n</html>")
        return parts.joined(separator: "\n")
    }

    private func buildSingleColorPageXHTML(title: String, imageFilename: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
          <meta charset="utf-8"/>
          <title>\(Self.xmlEscape(title))</title>
          <link rel="stylesheet" type="text/css" href="../Styles/style.css"/>
        </head>
        <body>
          <div class="illus-box"><img alt="\(Self.xmlEscape(title))" src="../Images/\(Self.xmlEscape(imageFilename))"/></div>
        </body>
        </html>
        """
    }

    private func buildMultiColorPageXHTML(title: String, imageFilenames: [String]) -> String {
        var lines = [
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
              <meta charset="utf-8"/>
              <title>\(Self.xmlEscape(title))</title>
              <link rel="stylesheet" type="text/css" href="../Styles/style.css"/>
            </head>
            <body>
            """
        ]
        for (idx, fname) in imageFilenames.enumerated() {
            lines.append("  <div class=\"color-page\"><img alt=\"彩插 \(idx + 1)\" src=\"../Images/\(Self.xmlEscape(fname))\"/></div>")
        }
        lines.append("</body>\n</html>")
        return lines.joined(separator: "\n")
    }

    private func buildChapterXHTML(
        chapter: ChapterContent,
        imageFilenames: [String: String],
        cleanCredits: Bool
    ) -> String {
        let safeTitle = Self.xmlEscape(chapter.chapter.title)
        var lines = [
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
              <meta charset="utf-8"/>
              <title>\(safeTitle)</title>
              <link rel="stylesheet" type="text/css" href="../Styles/style.css"/>
            </head>
            <body>
              <h1>\(safeTitle)</h1>
            """
        ]

        var bodyStarted = false
        for (idx, token) in chapter.tokens.enumerated() {
            switch token {
            case .paragraph(let text):
                if cleanCredits && !bodyStarted && idx < 12 &&
                    Self.creditPrefixes.contains(where: { text.hasPrefix($0) || text.contains("录入组") }) {
                    continue
                }
                bodyStarted = true
                lines.append("  <p>\(Self.xmlEscape(text))</p>")
            case .image(let url):
                bodyStarted = true
                if let fname = imageFilenames[url] {
                    lines.append("  <div class=\"illus-box\"><img alt=\"插图\" src=\"../Images/\(Self.xmlEscape(fname))\"/></div>")
                }
            }
        }

        lines.append("</body>\n</html>")
        return lines.joined(separator: "\n")
    }

    private func buildNCX(
        title: String,
        uuid: String,
        isMerged: Bool,
        frontItems: [(title: String, href: String)],
        volumeGroups: [EPUBNavVolumeGroup],
        backItems: [(title: String, href: String)]
    ) -> String {
        let depth = (isMerged && !volumeGroups.isEmpty) ? 2 : 1
        var lines = [
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
            "<!DOCTYPE ncx PUBLIC \"-//NISO//DTD ncx 2005-1//EN\" \"http://www.daisy.org/z3986/2005/ncx-2005-1.dtd\">",
            "<ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\">",
            "  <head>",
            "    <meta name=\"dtb:uid\" content=\"urn:uuid:\(Self.xmlEscape(uuid))\"/>",
            "    <meta name=\"dtb:depth\" content=\"\(depth)\"/>",
            "    <meta name=\"dtb:totalPageCount\" content=\"0\"/>",
            "    <meta name=\"dtb:maxPageNumber\" content=\"0\"/>",
            "  </head>",
            "  <docTitle><text>\(Self.xmlEscape(title))</text></docTitle>",
            "  <navMap>",
        ]

        var playOrder = 0
        func appendNavPoint(label: String, src: String, indent: String, closeImmediately: Bool = true) {
            playOrder += 1
            lines.append("\(indent)<navPoint id=\"navPoint-\(playOrder)\" playOrder=\"\(playOrder)\">")
            lines.append("\(indent)  <navLabel><text>\(Self.xmlEscape(label))</text></navLabel>")
            lines.append("\(indent)  <content src=\"\(Self.xmlEscape(src))\"/>")
            if closeImmediately {
                lines.append("\(indent)</navPoint>")
            }
        }

        for item in frontItems {
            appendNavPoint(label: item.title, src: item.href, indent: "    ")
        }

        for group in volumeGroups {
            if isMerged {
                appendNavPoint(label: group.volumeTitle, src: group.firstHref, indent: "    ", closeImmediately: false)
                for chap in group.chapters {
                    appendNavPoint(label: chap.title, src: chap.href, indent: "      ")
                }
                lines.append("    </navPoint>")
            } else {
                for chap in group.chapters {
                    appendNavPoint(label: chap.title, src: chap.href, indent: "    ")
                }
            }
        }

        for item in backItems {
            appendNavPoint(label: item.title, src: item.href, indent: "    ")
        }

        lines.append("  </navMap>")
        lines.append("</ncx>")
        return lines.joined(separator: "\n")
    }

    private func buildNavXHTML(
        title: String,
        isMerged: Bool,
        frontItems: [(title: String, href: String)],
        volumeGroups: [EPUBNavVolumeGroup],
        backItems: [(title: String, href: String)]
    ) -> String {
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<!DOCTYPE html>",
            "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\">",
            "<head>",
            "  <meta charset=\"utf-8\"/>",
            "  <title>\(Self.xmlEscape(title))</title>",
            "</head>",
            "<body>",
            "  <nav epub:type=\"toc\" id=\"toc\">",
            "    <h1>目录</h1>",
            "    <ol>",
        ]

        for item in frontItems {
            lines.append("      <li><a href=\"\(Self.xmlEscape(item.href))\">\(Self.xmlEscape(item.title))</a></li>")
        }
        for group in volumeGroups {
            if isMerged {
                lines.append("      <li><a href=\"\(Self.xmlEscape(group.firstHref))\">\(Self.xmlEscape(group.volumeTitle))</a>")
                lines.append("        <ol>")
                for chap in group.chapters {
                    lines.append("          <li><a href=\"\(Self.xmlEscape(chap.href))\">\(Self.xmlEscape(chap.title))</a></li>")
                }
                lines.append("        </ol>")
                lines.append("      </li>")
            } else {
                for chap in group.chapters {
                    lines.append("      <li><a href=\"\(Self.xmlEscape(chap.href))\">\(Self.xmlEscape(chap.title))</a></li>")
                }
            }
        }
        for item in backItems {
            lines.append("      <li><a href=\"\(Self.xmlEscape(item.href))\">\(Self.xmlEscape(item.title))</a></li>")
        }

        lines.append("    </ol>")
        lines.append("  </nav>")
        lines.append("</body>")
        lines.append("</html>")
        return lines.joined(separator: "\n")
    }

    private func buildOPF(
        version: EPUBVersion,
        uuid: String,
        title: String,
        seriesTitle: String,
        seriesIndex: Int?,
        author: String,
        book: BookDetail,
        coverId: String?,
        htmlDocs: [(id: String, href: String)],
        imageDocs: [(id: String, filename: String, mime: String)],
        spineRefs: [String],
        includeCover: Bool
    ) -> String {
        let isEPUB3 = version == .epub3
        let pkgVersion = isEPUB3 ? "3.0" : "2.0"

        var lines = [
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
            "<package version=\"\(pkgVersion)\" unique-identifier=\"BookId\" xmlns=\"http://www.idpf.org/2007/opf\">",
            "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:opf=\"http://www.idpf.org/2007/opf\">",
            "    <dc:identifier id=\"BookId\">urn:uuid:\(Self.xmlEscape(uuid))</dc:identifier>",
            "    <dc:language>zh</dc:language>",
            "    <dc:title>\(Self.xmlEscape(title))</dc:title>",
        ]

        if isEPUB3 {
            lines.append("    <dc:creator id=\"creator\">\(Self.xmlEscape(author))</dc:creator>")
            lines.append("    <meta refines=\"#creator\" property=\"role\" scheme=\"marc:relators\">aut</meta>")
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            let modified = isoFormatter.string(from: Date())
            lines.append("    <meta property=\"dcterms:modified\">\(modified)</meta>")
            lines.append("    <meta property=\"belongs-to-collection\" id=\"series\">\(Self.xmlEscape(seriesTitle))</meta>")
            lines.append("    <meta refines=\"#series\" property=\"collection-type\">series</meta>")
            if let seriesIndex {
                lines.append("    <meta refines=\"#series\" property=\"group-position\">\(seriesIndex)</meta>")
            }
        } else {
            lines.append("    <dc:creator opf:role=\"aut\" opf:file-as=\"\(Self.xmlEscape(author))\">\(Self.xmlEscape(author))</dc:creator>")
            lines.append("    <meta name=\"calibre:series\" content=\"\(Self.xmlEscape(seriesTitle))\"/>")
            if let seriesIndex {
                lines.append("    <meta name=\"calibre:series_index\" content=\"\(seriesIndex)\"/>")
            }
        }

        if !book.publisher.isEmpty {
            lines.append("    <dc:publisher>\(Self.xmlEscape(book.publisher))</dc:publisher>")
        }
        if !book.lastUpdated.isEmpty {
            lines.append("    <dc:date>\(Self.xmlEscape(book.lastUpdated))</dc:date>")
        }
        if !book.description.isEmpty {
            lines.append("    <dc:description>\(Self.xmlEscape(book.description))</dc:description>")
        }
        for tag in book.tags where !tag.isEmpty {
            lines.append("    <dc:subject>\(Self.xmlEscape(tag))</dc:subject>")
        }
        if let coverId {
            lines.append("    <meta name=\"cover\" content=\"\(Self.xmlEscape(coverId))\"/>")
        }

        lines.append("  </metadata>")
        lines.append("  <manifest>")
        lines.append("    <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>")
        lines.append("    <item id=\"style_css\" href=\"Styles/style.css\" media-type=\"text/css\"/>")
        if isEPUB3 {
            lines.append("    <item id=\"nav_xhtml\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>")
        }
        for doc in htmlDocs {
            lines.append("    <item id=\"\(Self.xmlEscape(doc.id))\" href=\"\(Self.xmlEscape(doc.href))\" media-type=\"application/xhtml+xml\"/>")
        }
        for img in imageDocs {
            let props = (isEPUB3 && img.id == coverId) ? " properties=\"cover-image\"" : ""
            lines.append("    <item id=\"\(Self.xmlEscape(img.id))\" href=\"Images/\(Self.xmlEscape(img.filename))\" media-type=\"\(img.mime)\"\(props)/>")
        }
        lines.append("  </manifest>")

        lines.append("  <spine toc=\"ncx\">")
        for ref in spineRefs {
            lines.append("    <itemref idref=\"\(Self.xmlEscape(ref))\"/>")
        }
        lines.append("  </spine>")

        if includeCover {
            lines.append("  <guide>")
            lines.append("    <reference type=\"cover\" title=\"封面\" href=\"Text/cover.xhtml\"/>")
            lines.append("  </guide>")
        }

        lines.append("</package>")
        return lines.joined(separator: "\n")
    }
}

private struct EPUBNavVolumeGroup {
    let volumeTitle: String
    let firstHref: String
    let chapters: [(title: String, href: String)]
}
