import AppKit
import Foundation
import XCTest
@testable import Wenku8Core

final class Wenku8CoreTests: XCTestCase {
    func testExtractBookId() {
        XCTAssertEqual(Wenku8Client.extractBookId(from: "3115"), "3115")
        XCTAssertEqual(Wenku8Client.extractBookId(from: "https://www.wenku8.cc/book/3115.htm"), "3115")
        XCTAssertEqual(Wenku8Client.extractBookId(from: "https://www.wenku8.net/novel/3/3115/index.htm"), "3115")
        XCTAssertEqual(Wenku8Client.extractBookId(from: "bad"), "")
    }

    func testCookieDiagnosticDetectsForeignAndValidCookies() {
        let bing = Wenku8Client.diagnoseCookieFormat("MUID=20960C28; ANON=A=123; NAP=V=1.9")
        XCTAssertFalse(bing.isLikelyValidFormat)
        XCTAssertTrue(bing.isForeignSiteCookie)

        let valid = Wenku8Client.diagnoseCookieFormat("Cookie: jieqiUserInfo=abc; PHPSESSID=xyz123")
        XCTAssertTrue(valid.isLikelyValidFormat)
        XCTAssertFalse(valid.isForeignSiteCookie)
        XCTAssertEqual(valid.normalizedCookie, "jieqiUserInfo=abc; PHPSESSID=xyz123")
    }

    func testParseReviewThreadFloorAndNestedReplies() {
        let html = """
        <html><body><div id="content">
          <table class="grid"><tr><th><strong>主题：讨论帖</strong></th></tr></table>
          <table class="grid"><tr>
            <td class="odd"><img class="avatar" src="/images/noavatar.jpg"/><strong><a href="/userpage.php?uid=1">楼主A</a></strong><br/>普通会员<br/></td>
            <td class="even">
              <div style="float:left;"><strong>讨论帖</strong></div>
              <div style="float:right;">2026-11-10 17:43:14 | <a href="#yid1" name="yid1">1#</a></div>
              <hr/>
              <div style="width:100%;">主楼内容</div>
            </td>
          </tr></table>
          <table class="grid"><tr>
            <td class="odd"><strong><a href="/userpage.php?uid=2">回复B</a></strong><br/>高级会员<br/></td>
            <td class="even">
              <div style="float:right;">2026-11-10 18:00:00 | <a href="#yid2" name="yid2">2#</a></div>
              <hr/>
              <div style="width:100%;">回复 1# 确实如此</div>
            </td>
          </tr></table>
          <table class="grid"><tr>
            <td class="odd"><strong><a href="/userpage.php?uid=3">回复C</a></strong><br/>书友<br/></td>
            <td class="even">
              <div style="float:right;">2026-11-10 18:10:00 | <a href="#yid3" name="yid3">3#</a></div>
              <hr/>
              <div style="width:100%;">@2# 赞同楼上</div>
            </td>
          </tr></table>
          <table class="grid">
            <caption>回复书评：</caption>
            <tr>
              <td class="odd">内容(每帖+1积分)</td>
              <td class="even"><textarea name="pcontent"></textarea><script>loadJs("/scripts/ubbeditor_gbk.js", function(){UBBEditor.Create("pcontent");});</script></td>
            </tr>
          </table>
        </div></body></html>
        """
        let posts = Wenku8Client.parseReviewThreadPage(html: html, baseURL: "https://www.wenku8.cc")
        XCTAssertEqual(posts.count, 3)
        XCTAssertEqual(posts[0].floor, 1)
        XCTAssertEqual(posts[0].author, "楼主A")
        XCTAssertEqual(posts[1].floor, 2)
        XCTAssertEqual(posts[1].replyToFloor, 1)
        XCTAssertEqual(posts[2].floor, 3)
        XCTAssertEqual(posts[2].replyToFloor, 2)
    }

    func testParseBookPageMetadataAndRecommendations() throws {
        let html = """
        <html><body><div id="content">
          <table>
            <tr><td><b>测试轻小说 &amp; 冒险</b></td></tr>
            <tr>
              <td>文库分类：集英社</td>
              <td>小说作者：猫玄</td>
              <td>文章状态：连载中</td>
              <td>最后更新：2026-06-12</td>
              <td>全文长度：530043字</td>
            </tr>
          </table>
          <table><tr>
            <td><img src="http://img.wenku8.com/image/3/3115/3115s.jpg"/></td>
            <td>
              <span class="hottext"><b>作品Tags：校园 青春 恋爱</b></span>
              <span class="hottext"><b>作品热度：A级</b></span>
              <span class="hottext">最近章节：</span><span>第二卷 插图</span>
              <span class="hottext">内容简介：</span><span>第一行简介<br/>第二行简介</span>
            </td>
          </tr></table>
          <a href="/novel/3/3115/index.htm">小说目录</a>
          <a href="/book/3972.htm">推荐书A</a>
        </div></body></html>
        """

        let parsed = try Wenku8Client.parseBookPage(
            html: html,
            bookURL: "https://www.wenku8.cc/book/3115.htm",
            baseURL: "https://www.wenku8.cc"
        )
        XCTAssertEqual(parsed.title, "测试轻小说 & 冒险")
        XCTAssertEqual(parsed.publisher, "集英社")
        XCTAssertEqual(parsed.author, "猫玄")
        XCTAssertEqual(parsed.status, "连载中")
        XCTAssertEqual(parsed.lastUpdated, "2026-06-12")
        XCTAssertEqual(parsed.wordCount, "530043字")
        XCTAssertEqual(parsed.tags, ["校园", "青春", "恋爱"])
        XCTAssertTrue(parsed.description.contains("第一行简介"))
        XCTAssertEqual(parsed.catalogURL, "https://www.wenku8.cc/novel/3/3115/index.htm")
        XCTAssertEqual(parsed.recommendations.first?.id, "3972")
    }

    func testParseCatalogAndChapterInlineImage() throws {
        let catalogHTML = """
        <html><body>
          <div id="title">测试小说</div>
          <div id="info">作者：测试君</div>
          <table class="css">
            <tr><td class="vcss">第一卷</td></tr>
            <tr>
              <td class="ccss"><a href="101.htm">插图</a></td>
              <td class="ccss"><a href="102.htm">第一章</a></td>
            </tr>
          </table>
        </body></html>
        """
        let (title, author, volumes) = try Wenku8Client.parseCatalogPage(
            html: catalogHTML,
            catalogURL: "https://www.wenku8.cc/novel/3/3115/index.htm"
        )
        XCTAssertEqual(title, "测试小说")
        XCTAssertEqual(author, "测试君")
        XCTAssertEqual(volumes.count, 1)
        XCTAssertEqual(volumes[0].chapters.count, 2)
        XCTAssertTrue(volumes[0].chapters[0].isIllustrationChapter)
        XCTAssertFalse(volumes[0].chapters[1].isIllustrationChapter)

        let chapHTML = """
        <html><body><div id="content">
          <ul id="contentdp">广告</ul>
          第一段<br/><br/>
          <div class="divimage"><img src="https://pic.wenku8.com/test.jpg"/></div>
          第二段
        </div></body></html>
        """
        let content = try Wenku8Client.parseChapterContent(html: chapHTML, chapter: volumes[0].chapters[1])
        XCTAssertEqual(content.imageURLs, ["https://pic.wenku8.com/test.jpg"])
        XCTAssertEqual(content.tokens.count, 3)
    }

    func testBuildMergedEPUB3WithStylesAndNav() throws {
        let tempOut = FileManager.default.temporaryDirectory.appendingPathComponent("swift_epub_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempOut) }

        let img = NSImage(size: NSSize(width: 120, height: 180))
        img.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 180).fill()
        img.unlockFocus()
        let tiff = img.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        let jpgData = rep.representation(using: .jpeg, properties: [:])!

        let imgURL = "https://img.example.com/1.jpg"
        let asset = DownloadedImageAsset(url: imgURL, data: jpgData, fileExtension: ".jpg", mimeType: "image/jpeg", width: 120, height: 180)

        let ch1 = ChapterItem(id: "c1", title: "序章 & 开始", url: "https://www.wenku8.cc/1.htm", volumeIndex: 1, chapterIndex: 0, isIllustrationChapter: false)
        let ch2 = ChapterItem(id: "c2", title: "第二卷 第一章", url: "https://www.wenku8.cc/2.htm", volumeIndex: 2, chapterIndex: 0, isIllustrationChapter: false)
        let v1 = VolumeItem(id: "v1", index: 1, title: "第一卷", chapters: [ch1])
        let v2 = VolumeItem(id: "v2", index: 2, title: "第二卷", chapters: [ch2])

        let book = BookDetail(
            bookId: "3115",
            baseURL: "https://www.wenku8.cc",
            title: "测试合集",
            author: "猫玄",
            publisher: "集英社",
            status: "连载中",
            lastUpdated: "2026-06-12",
            wordCount: "50万字",
            popularity: "A级",
            latestChapter: "第二卷",
            tags: ["校园", "恋爱"],
            description: "简介测试",
            coverURL: imgURL,
            catalogURL: "https://www.wenku8.cc/novel/3/3115/index.htm",
            volumes: [v1, v2],
            recommendations: []
        )

        var cfg = AssemblyConfig()
        cfg.epubVersion = .epub3
        cfg.exportMode = .mergedSingle
        cfg.cleanCreditsHeader = true

        let inputs = [
            VolumeBuildInput(
                volume: v1,
                chapters: [ChapterContent(chapter: ch1, tokens: [.paragraph("台版 转自 轻之国度"), .paragraph("正文第一段"), .image(imgURL)], imageURLs: [imgURL])],
                illustrationChapter: nil
            ),
            VolumeBuildInput(
                volume: v2,
                chapters: [ChapterContent(chapter: ch2, tokens: [.paragraph("正文第二卷")], imageURLs: [])],
                illustrationChapter: nil
            ),
        ]

        let artifact = try EPUBBuilder().buildEPUB(
            book: book,
            volumes: inputs,
            images: [imgURL: asset],
            outputDirectory: tempOut,
            config: cfg
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.filePath))
        XCTAssertGreaterThan(artifact.fileSizeBytes, 500)

        // Verify unzip lists nav.xhtml, toc.ncx, content.opf, style.css, info.xhtml
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-l", artifact.filePath]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        let listing = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(listing.contains("mimetype"))
        XCTAssertTrue(listing.contains("OEBPS/nav.xhtml"))
        XCTAssertTrue(listing.contains("OEBPS/toc.ncx"))
        XCTAssertTrue(listing.contains("OEBPS/content.opf"))
        XCTAssertTrue(listing.contains("OEBPS/Styles/style.css"))
        XCTAssertTrue(listing.contains("OEBPS/Text/info.xhtml"))
    }
}
