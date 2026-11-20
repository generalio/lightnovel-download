import io
import os
import zipfile

from PIL import Image
import pytest

from Editer import DownloadCancelled, Editer
import lightnovel
import utils


def _make_image_bytes(fmt='JPEG', size=(120, 180), color=(30, 120, 200)):
    buf = io.BytesIO()
    Image.new('RGB', size, color=color).save(buf, format=fmt)
    return buf.getvalue()


def test_extract_book_id():
    assert utils.extract_book_id('3138') == '3138'
    assert utils.extract_book_id('  12345  ') == '12345'
    assert utils.extract_book_id('https://www.wenku8.net/book/3138.htm') == '3138'
    assert utils.extract_book_id('https://www.wenku8.cc/novel/3/3138/index.htm') == '3138'
    assert utils.extract_book_id('invalid-book') == ''


def test_parse_volume_spec():
    assert lightnovel.parse_volume_spec('') is None
    assert lightnovel.parse_volume_spec('2') == [2]
    assert lightnovel.parse_volume_spec('1-1') == [1]
    assert lightnovel.parse_volume_spec('1-3') == [1, 2, 3]
    assert lightnovel.parse_volume_spec('3, 1, 3, 2') == [3, 1, 2]
    assert lightnovel.parse_volume_spec('1，2') == [1, 2]

    with pytest.raises(ValueError):
        lightnovel.parse_volume_spec('3-1')
    with pytest.raises(ValueError):
        lightnovel.parse_volume_spec('0')
    with pytest.raises(ValueError):
        lightnovel.parse_volume_spec('abc')


def test_text2htmls_escaping_and_large_image_index():
    text = '第一行 & <测试>\n[img:105]\n第二行 "引号"'
    lines = utils.text2htmls('第1话 <序> & 启程', text, img_files={'105': '105.png'})
    joined = ''.join(lines)
    assert '&amp;' in joined
    assert '&lt;测试&gt;' in joined
    assert '../Images/105.png' in joined
    assert '&lt;序&gt;' in joined


def test_content_html_omits_xcolor_when_no_color_page():
    opf_no_color = ''.join(
        utils.get_content_html(
            '书名 & 测试',
            '作者<A>',
            num_chap=2,
            img_exist=False,
            img_files=['00.jpg'],
            cover_filename='00.jpg',
        )
    )
    assert 'id="xcolor"' not in opf_no_color
    assert 'idref="xcolor"' not in opf_no_color
    assert '&amp;' in opf_no_color
    assert '书名' in opf_no_color

    opf_with_color = ''.join(
        utils.get_content_html(
            '书名',
            '作者',
            num_chap=1,
            img_exist=True,
            img_files=['00.jpg', '01.png'],
            cover_filename='00.jpg',
        )
    )
    assert 'id="xcolor"' in opf_with_color
    assert 'idref="xcolor"' in opf_with_color
    assert 'media-type="image/png"' in opf_with_color


def test_editer_end_to_end_inline_and_color_dedup(tmp_path, monkeypatch):
    jpg_bytes = _make_image_bytes('JPEG', (200, 300))
    png_bytes = _make_image_bytes('PNG', (240, 320), color=(200, 50, 50))

    pages = {
        'https://www.wenku8.cc/book/3138.htm': (
            '<html><body>'
            '<div id="content">'
            '<table><tr><td>文库分类：角川文库</td><td>小说作者：测试</td><td>文章状态：已完结</td>'
            '<td>最后更新：2026-01-01</td><td>全文长度：10000字</td></tr></table>'
            '<span><b>作品Tags：校园 恋爱</b></span>'
            '<span>内容简介：</span><span>一段精彩简介。</span>'
            '<img src="https://img.example.com/series_cover.jpg"/></div>'
            '<a href="/novel/3/3138/index.htm">小说目录</a>'
            '</body></html>'
        ),
        'https://www.wenku8.cc/novel/3/3138/index.htm': (
            '<html><body>'
            '<div id="title">测试轻小说 &amp; 冒险</div>'
            '<div id="info">作者：测试作者</div>'
            '<table class="css">'
            '<tr><td class="vcss" colspan="4">第一卷</td></tr>'
            '<tr><td class="ccss"><a href="1001.htm">插图</a></td>'
            '<td class="ccss"><a href="1002.htm">序章 &lt;开始&gt;</a></td></tr>'
            '</table></body></html>'
        ),
        'https://www.wenku8.cc/novel/3/3138/1001.htm': (
            '<html><body><div id="content">'
            '<img src="https://img.example.com/vol1_cover.jpg" class="imagecontent"/>'
            '<img src="https://img.example.com/inline_shared.png" class="imagecontent"/>'
            '<img src="https://img.example.com/color_only.png" class="imagecontent"/>'
            '</div></body></html>'
        ),
        'https://www.wenku8.cc/novel/3/3138/1002.htm': (
            '<html><body><div id="content">'
            '<ul id="contentdp">广告文本</ul>'
            '正文第一段 &amp; 测试<br/><br/>'
            '<div class="divimage"><img src="https://img.example.com/inline_shared.png"/></div>'
            '正文第二段'
            '</div></body></html>'
        ),
    }
    images = {
        'https://img.example.com/vol1_cover.jpg': jpg_bytes,
        'https://img.example.com/inline_shared.png': png_bytes,
        'https://img.example.com/color_only.png': png_bytes,
    }

    editer = Editer(
        root_path=str(tmp_path),
        book_no='https://www.wenku8.net/book/3138.htm',
        volume_no=1,
        split_color_pages=False,
    )
    monkeypatch.setattr(editer, 'get_html', lambda url, is_gbk=True: pages[url])
    monkeypatch.setattr(editer, 'get_html_img', lambda url, is_buffer=False: images[url])

    assert editer.get_index_url() is True
    editer.check_volume()
    editer.get_text()
    editer.get_image()
    editer.get_cover()
    editer.get_toc()
    editer.get_content()
    editer.get_epub_head()
    epub_path = editer.get_epub()

    assert os.path.exists(epub_path)
    assert not os.path.exists(editer.temp_path)

    with zipfile.ZipFile(epub_path, 'r') as zf:
        infos = zf.infolist()
        assert infos[0].filename == 'mimetype'
        assert infos[0].compress_type == zipfile.ZIP_STORED

        names = set(zf.namelist())
        assert 'OEBPS/Styles/style.css' in names
        assert 'OEBPS/Text/info.xhtml' in names
        assert 'OEBPS/Text/00.xhtml' in names
        assert 'OEBPS/Text/color.xhtml' in names
        assert 'OEBPS/Images/00.jpg' in names
        assert 'OEBPS/Images/01.png' in names
        assert 'OEBPS/Images/02.png' in names

        opf_xml = zf.read('OEBPS/content.opf').decode('utf-8')
        assert '<dc:publisher>角川文库</dc:publisher>' in opf_xml
        assert '<dc:subject>校园</dc:subject>' in opf_xml
        assert '一段精彩简介' in opf_xml

        ncx_xml = zf.read('OEBPS/toc.ncx').decode('utf-8')
        assert '测试轻小说 &amp; 冒险-第一卷' in ncx_xml
        assert 'Text/info.xhtml' in ncx_xml

        chap_xml = zf.read('OEBPS/Text/00.xhtml').decode('utf-8')
        assert '广告文本' not in chap_xml
        assert '../Images/01.png' in chap_xml
        assert '正文第一段 &amp; 测试' in chap_xml

        # 01.png appeared in body chapter, so color.xhtml should only keep 02.png
        color_xml = zf.read('OEBPS/Text/color.xhtml').decode('utf-8')
        assert '../Images/01.png' not in color_xml
        assert '../Images/02.png' in color_xml


def test_editer_cancel_raises_and_cleans_up(tmp_path):
    import threading

    cancel = threading.Event()
    cancel.set()
    editer = Editer(root_path=str(tmp_path), book_no='3138', volume_no=1, cancel_event=cancel)
    with pytest.raises(DownloadCancelled):
        editer.fetch_book_info()


def test_volume_without_color_page_produces_valid_opf(tmp_path, monkeypatch):
    jpg_bytes = _make_image_bytes('JPEG', (200, 300))
    pages = {
        'https://www.wenku8.cc/book/12345.htm': (
            '<html><body>'
            '<div id="content"><img src="https://img.example.com/cover.jpg"/></div>'
            '<a href="/novel/12/12345/index.htm">小说目录</a>'
            '</body></html>'
        ),
        'https://www.wenku8.cc/novel/12/12345/index.htm': (
            '<html><body>'
            '<div id="title">无彩插测试</div>'
            '<div id="info">作者：测试君</div>'
            '<table class="css">'
            '<tr><td class="vcss" colspan="4">第一卷</td></tr>'
            '<tr><td class="ccss"><a href="1.htm">第一章</a></td></tr>'
            '</table></body></html>'
        ),
        'https://www.wenku8.cc/novel/12/12345/1.htm': (
            '<html><body><div id="content">纯文本内容</div></body></html>'
        ),
    }

    editer = Editer(root_path=str(tmp_path), book_no='12345', volume_no=1)
    monkeypatch.setattr(editer, 'get_html', lambda url, is_gbk=True: pages[url])
    monkeypatch.setattr(editer, 'get_html_img', lambda url, is_buffer=False: jpg_bytes)

    assert editer.get_index_url() is True
    editer.check_volume()
    editer.get_text()
    editer.get_image()
    editer.get_cover()
    editer.get_toc()
    editer.get_content()
    editer.get_epub_head()
    epub_path = editer.get_epub()

    with zipfile.ZipFile(epub_path, 'r') as zf:
        names = set(zf.namelist())
        assert 'OEBPS/Text/color.xhtml' not in names
        opf = zf.read('OEBPS/content.opf').decode('utf-8')
        assert 'xcolor' not in opf
        assert '<meta name="cover" content="x00.jpg"/>' in opf


def test_official_mirror_fallback_from_cc_to_net(tmp_path, monkeypatch):
    editer = Editer(root_path=str(tmp_path), book_no='3115', volume_no=1)
    assert editer.url_head == 'https://www.wenku8.cc'

    def fake_get_html(url, is_gbk=True):
        if url.startswith('https://www.wenku8.cc'):
            raise RuntimeError(f'网络请求失败：{url}')
        if url == 'https://www.wenku8.net/book/3115.htm':
            return '<html><body><a href="/novel/3/3115/index.htm">小说目录</a></body></html>'
        if url == 'https://www.wenku8.net/novel/3/3115/index.htm':
            return (
                '<html><body><div id="title">主站回退书名</div>'
                '<div id="info">作者：测试作者</div></body></html>'
            )
        raise AssertionError(f'Unexpected url: {url}')

    monkeypatch.setattr(editer, 'get_html', fake_get_html)
    assert editer.fetch_book_info() is True
    assert editer.url_head == 'https://www.wenku8.net'
    assert editer.title == '主站回退书名'


def test_cli_merged_epub3_and_clean_credits(tmp_path, monkeypatch):
    jpg_bytes = _make_image_bytes('JPEG', (200, 300))
    pages = {
        'https://www.wenku8.cc/book/8888.htm': (
            '<html><body>'
            '<div id="content"><img src="https://img.example.com/c.jpg"/></div>'
            '<a href="/novel/8/8888/index.htm">小说目录</a>'
            '</body></html>'
        ),
        'https://www.wenku8.cc/novel/8/8888/index.htm': (
            '<html><body>'
            '<div id="title">合集测试</div>'
            '<div id="info">作者：作者A</div>'
            '<table class="css">'
            '<tr><td class="vcss">第一卷</td></tr>'
            '<tr><td class="ccss"><a href="1.htm">序章</a></td></tr>'
            '<tr><td class="vcss">第二卷</td></tr>'
            '<tr><td class="ccss"><a href="2.htm">第二卷第一章</a></td></tr>'
            '</table></body></html>'
        ),
        'https://www.wenku8.cc/novel/8/8888/1.htm': (
            '<html><body><div id="content">台版 转自 轻之国度<br/>录入：测试<br/>正文一</div></body></html>'
        ),
        'https://www.wenku8.cc/novel/8/8888/2.htm': (
            '<html><body><div id="content">正文二</div></body></html>'
        ),
    }

    editer = Editer(
        root_path=str(tmp_path),
        book_no='8888',
        epub_version='3',
        clean_credits=True,
    )
    monkeypatch.setattr(editer, 'get_html', lambda url, is_gbk=True: pages[url])
    monkeypatch.setattr(editer, 'get_html_img', lambda url, is_buffer=False: jpg_bytes)

    epub_file = editer.download_merged_volumes([1, 2])
    assert os.path.exists(epub_file)
    with zipfile.ZipFile(epub_file, 'r') as zf:
        names = set(zf.namelist())
        assert 'OEBPS/nav.xhtml' in names
        opf = zf.read('OEBPS/content.opf').decode('utf-8')
        assert 'version="3.0"' in opf
        assert 'belongs-to-collection' in opf
        ncx = zf.read('OEBPS/toc.ncx').decode('utf-8')
        assert 'dtb:depth" content="2"' in ncx
        ch0 = zf.read('OEBPS/Text/00.xhtml').decode('utf-8')
        assert '台版 转自' not in ch0
        assert '正文一' in ch0


def test_cli_review_thread_skips_reply_form_script(tmp_path, monkeypatch):
    html_text = """
    <html><body><div id="content">
      <table class="grid"><tr><th><strong>主题</strong></th></tr></table>
      <table class="grid"><tr>
        <td class="odd"><strong><a href="/userpage.php?uid=1">用户1</a></strong></td>
        <td class="even"><div style="float:right;">2026-11-10 | <a href="#yid1">1#</a></div><hr/><div>主楼</div></td>
      </tr></table>
      <table class="grid">
        <caption>回复书评：</caption>
        <tr>
          <td class="odd">内容(每帖+1积分)</td>
          <td class="even"><textarea name="pcontent"></textarea><script>loadJs("/scripts/ubbeditor_gbk.js");</script></td>
        </tr>
      </table>
    </div></body></html>
    """
    editer = Editer(root_path=str(tmp_path), book_no='3115')
    monkeypatch.setattr(editer, 'get_html', lambda url, is_gbk=True: html_text)
    posts = editer.fetch_review_thread('319681')
    assert len(posts) == 1
    assert posts[0]['author'] == '用户1'
    assert 'ubbeditor' not in posts[0]['content']
