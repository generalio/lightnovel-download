from datetime import datetime, timezone
import html
import io
import os
import re
import uuid
from typing import Dict, List, Optional, Tuple, Union

from PIL import Image

_IMG_TAG_RE = re.compile(r'^\[img:(\d+)\]$')
_BOOK_URL_RE = re.compile(r'(?:/book/|/novel/\d+/)(\d+)')
_CREDIT_PREFIXES = (
    '台版 ',
    '网译版',
    '轻之国度',
    '天使动漫',
    '图源：',
    '图源:',
    '扫图：',
    '扫图:',
    '录入：',
    '录入:',
    '修图：',
    '修图:',
    '翻译：',
    '翻译:',
    '校对：',
    '校对:',
    '润色：',
    '润色:',
    '转自 ',
)

_EXT_MIME_MAP = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.bmp': 'image/bmp',
}


def extract_book_id(raw_input: str) -> str:
    """Extract numeric wenku8 book ID from a plain ID or a wenku8 URL."""
    text = (raw_input or '').strip()
    if not text:
        return ''
    if text.isdigit():
        return text
    match = _BOOK_URL_RE.search(text)
    if match:
        return match.group(1)
    return ''


def guess_image_ext_and_mime(data: bytes, url: str = '') -> Tuple[str, str]:
    """Detect actual image format from bytes (and fallback to URL suffix)."""
    if data:
        if data.startswith(b'\xff\xd8\xff'):
            return '.jpg', 'image/jpeg'
        if data.startswith(b'\x89PNG\r\n\x1a\n'):
            return '.png', 'image/png'
        if data.startswith((b'GIF87a', b'GIF89a')):
            return '.gif', 'image/gif'
        if len(data) >= 12 and data[:4] == b'RIFF' and data[8:12] == b'WEBP':
            return '.webp', 'image/webp'
        try:
            with Image.open(io.BytesIO(data)) as img:
                fmt = (img.format or '').upper()
            fmt_map = {
                'JPEG': ('.jpg', 'image/jpeg'),
                'PNG': ('.png', 'image/png'),
                'GIF': ('.gif', 'image/gif'),
                'WEBP': ('.webp', 'image/webp'),
                'BMP': ('.bmp', 'image/bmp'),
            }
            if fmt in fmt_map:
                return fmt_map[fmt]
        except Exception:
            pass

    lower_url = (url or '').split('?', 1)[0].lower()
    for ext, mime in _EXT_MIME_MAP.items():
        if lower_url.endswith(ext):
            return ('.jpg' if ext == '.jpeg' else ext), mime
    return '.jpg', 'image/jpeg'


def get_mime_type(filename: str) -> str:
    """Return EPUB media-type for an image filename."""
    _, ext = os.path.splitext(filename.lower())
    return _EXT_MIME_MAP.get(ext, 'image/jpeg')


def get_cover_html(img_w: int, img_h: int, cover_filename: str = '00.jpg') -> List[str]:
    """Build cover XHTML document."""
    safe_cover = html.escape(cover_filename, quote=True)
    return [
        '<?xml version="1.0" encoding="UTF-8" standalone="no" ?>\n',
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"\n',
        '"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">\n',
        '<html xmlns="http://www.w3.org/1999/xhtml">\n',
        '<head>\n',
        '  <title>Cover</title>\n',
        '</head>\n',
        '<body>\n',
        '  <div style="text-align: center; padding: 0pt; margin: 0pt;">\n',
        (
            f'    <svg xmlns="http://www.w3.org/2000/svg" height="100%" '
            f'preserveAspectRatio="xMidYMid meet" version="1.1" '
            f'viewBox="0 0 {int(img_w)} {int(img_h)}" width="100%" '
            f'xmlns:xlink="http://www.w3.org/1999/xlink">\n'
        ),
        f'      <image width="{int(img_w)}" height="{int(img_h)}" xlink:href="../Images/{safe_cover}"/>\n',
        '    </svg>\n',
        '  </div>\n',
        '</body>\n',
        '</html>',
    ]


def text2htmls(
    chap_name: str,
    text: str,
    img_files: Optional[Dict[str, str]] = None,
    clean_credits: bool = False,
) -> List[str]:
    """Convert chapter plain text with [img:XX] markers into valid XHTML lines."""
    safe_chap_name = html.escape(chap_name)
    text_body = ['<body>\n', f'<h1>{safe_chap_name}</h1>\n']

    body_started = False
    for idx, raw_line in enumerate(text.splitlines()):
        stripped = raw_line.strip()
        if not stripped:
            continue
        img_match = _IMG_TAG_RE.match(stripped)
        if img_match:
            body_started = True
            img_no = img_match.group(1)
            filename = img_files.get(img_no, f'{img_no}.jpg') if img_files else f'{img_no}.jpg'
            safe_filename = html.escape(filename, quote=True)
            safe_alt = html.escape(img_no, quote=True)
            text_body.append(
                f'  <div class="illus-box"><img alt="{safe_alt}" src="../Images/{safe_filename}"/></div>\n'
            )
        else:
            if clean_credits and not body_started and idx < 12:
                if any(stripped.startswith(p) or '录入组' in stripped for p in _CREDIT_PREFIXES):
                    continue
            body_started = True
            text_body.append(f'<p>{html.escape(stripped)}</p>\n')

    text_body.append('</body>\n')

    text_head = [
        '<?xml version="1.0" encoding="UTF-8" standalone="no" ?>\n',
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"\n',
        '"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">\n',
        '<html xmlns="http://www.w3.org/1999/xhtml">\n',
        '<head>\n',
        f'<title>{safe_chap_name}</title>\n',
        '<link rel="stylesheet" type="text/css" href="../Styles/style.css"/>\n',
        '<style type="text/css">p{text-indent:2em;line-height:1.6;} img{max-width:100%;height:auto;}</style>\n',
        '</head>\n',
    ]
    return text_head + text_body + ['</html>']


def get_toc_html(
    title: str,
    chap_names: List[str],
    chap_files: Optional[List[str]] = None,
    book_uuid: Optional[str] = None,
    extra_nav_items: Optional[List[Tuple[str, str]]] = None,
    volume_groups: Optional[List[Tuple[str, List[Tuple[str, str]]]]] = None,
    back_nav_items: Optional[List[Tuple[str, str]]] = None,
) -> List[str]:
    """Build EPUB NCX navigation file (supporting single-level or 2-level merged volume tree)."""
    uid = book_uuid or str(uuid.uuid4())
    safe_title = html.escape(title)
    depth = 2 if volume_groups else 1
    toc_htmls = [
        '<?xml version="1.0" encoding="utf-8"?>\n',
        '<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN"\n',
        '   "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">\n\n',
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n',
        '  <head>\n',
        f'    <meta name="dtb:uid" content="urn:uuid:{html.escape(uid, quote=True)}" />\n',
        f'    <meta name="dtb:depth" content="{depth}" />\n',
        '    <meta name="dtb:totalPageCount" content="0" />\n',
        '    <meta name="dtb:maxPageNumber" content="0" />\n',
        '  </head>\n',
        '  <docTitle>\n',
        f'    <text>{safe_title}</text>\n',
        '  </docTitle>\n',
        '  <navMap>\n',
    ]

    play_order = 0

    def _emit_point(label: str, src: str, indent: str, close: bool = True) -> None:
        nonlocal play_order
        play_order += 1
        toc_htmls.extend([
            f'{indent}<navPoint id="navPoint-{play_order}" playOrder="{play_order}">\n',
            f'{indent}  <navLabel><text>{html.escape(label)}</text></navLabel>\n',
            f'{indent}  <content src="{html.escape(src, quote=True)}"/>\n',
        ])
        if close:
            toc_htmls.append(f'{indent}</navPoint>\n')

    for label, src in (extra_nav_items or []):
        _emit_point(label, src, '    ')

    if volume_groups:
        for vol_title, items in volume_groups:
            if not items:
                continue
            _emit_point(vol_title, items[0][1], '    ', close=False)
            for label, src in items:
                _emit_point(label, src, '      ')
            toc_htmls.append('    </navPoint>\n')
    else:
        for chap_no, chap_name in enumerate(chap_names):
            src = chap_files[chap_no] if chap_files else f'Text/{str(chap_no).zfill(2)}.xhtml'
            _emit_point(chap_name, src, '    ')

    for label, src in (back_nav_items or []):
        _emit_point(label, src, '    ')

    toc_htmls.extend(['  </navMap>\n', '</ncx>'])
    return toc_htmls


def get_nav_xhtml(
    title: str,
    chap_names: List[str],
    chap_files: Optional[List[str]] = None,
    extra_nav_items: Optional[List[Tuple[str, str]]] = None,
    volume_groups: Optional[List[Tuple[str, List[Tuple[str, str]]]]] = None,
    back_nav_items: Optional[List[Tuple[str, str]]] = None,
) -> List[str]:
    """Build EPUB 3.0 nav.xhtml navigation document."""
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>\n',
        '<!DOCTYPE html>\n',
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">\n',
        '<head>\n',
        '  <meta charset="utf-8"/>\n',
        f'  <title>{html.escape(title)}</title>\n',
        '</head>\n',
        '<body>\n',
        '  <nav epub:type="toc" id="toc">\n',
        '    <h1>目录</h1>\n',
        '    <ol>\n',
    ]
    for label, src in (extra_nav_items or []):
        lines.append(f'      <li><a href="{html.escape(src, quote=True)}">{html.escape(label)}</a></li>\n')
    if volume_groups:
        for vol_title, items in volume_groups:
            if not items:
                continue
            lines.append(f'      <li><a href="{html.escape(items[0][1], quote=True)}">{html.escape(vol_title)}</a>\n')
            lines.append('        <ol>\n')
            for label, src in items:
                lines.append(f'          <li><a href="{html.escape(src, quote=True)}">{html.escape(label)}</a></li>\n')
            lines.append('        </ol>\n')
            lines.append('      </li>\n')
    else:
        for chap_no, chap_name in enumerate(chap_names):
            src = chap_files[chap_no] if chap_files else f'Text/{str(chap_no).zfill(2)}.xhtml'
            lines.append(f'      <li><a href="{html.escape(src, quote=True)}">{html.escape(chap_name)}</a></li>\n')
    for label, src in (back_nav_items or []):
        lines.append(f'      <li><a href="{html.escape(src, quote=True)}">{html.escape(label)}</a></li>\n')
    lines.extend(['    </ol>\n', '  </nav>\n', '</body>\n', '</html>'])
    return lines


def get_style_css(
    text_indent_em: float = 2.0,
    line_height: float = 1.65,
    paragraph_spacing_em: float = 0.5,
) -> str:
    """Build shared external EPUB stylesheet."""
    return (
        'body {\n'
        '  margin: 1em 1.2em;\n'
        f'  line-height: {line_height};\n'
        '}\n'
        'h1, h2 {\n'
        '  text-align: center;\n'
        '  margin: 1em 0 1.2em 0;\n'
        '  line-height: 1.4;\n'
        '}\n'
        'p {\n'
        f'  text-indent: {text_indent_em}em;\n'
        f'  margin: 0 0 {paragraph_spacing_em}em 0;\n'
        '}\n'
        '.illus-box {\n'
        '  text-align: center;\n'
        '  margin: 0.8em 0;\n'
        '  text-indent: 0;\n'
        '}\n'
        'img {\n'
        '  max-width: 100%;\n'
        '  height: auto;\n'
        '}\n'
        '.color-page {\n'
        '  text-align: center;\n'
        '  page-break-after: always;\n'
        '  break-after: page;\n'
        '  margin: 0;\n'
        '}\n'
        '.info-box {\n'
        '  margin: 1em 0;\n'
        '  line-height: 1.6;\n'
        '}\n'
        '.info-box p {\n'
        '  text-indent: 0;\n'
        '  margin: 0.3em 0;\n'
        '}\n'
        '.tag {\n'
        '  display: inline-block;\n'
        '  padding: 0.1em 0.45em;\n'
        '  margin: 0.15em;\n'
        '  border: 1px solid #888;\n'
        '  border-radius: 4px;\n'
        '  font-size: 0.85em;\n'
        '}\n'
    )


def get_info_html(
    title: str,
    volume_name: str,
    author: str,
    publisher: str = '',
    status: str = '',
    last_updated: str = '',
    word_count: str = '',
    tags: Optional[List[str]] = None,
    description: str = '',
    cover_filename: str = '',
) -> List[str]:
    """Build an informative front-matter page with book metadata and synopsis."""
    safe_title = html.escape(title)
    safe_vol = html.escape(volume_name)
    safe_author = html.escape(author or '未知')
    lines = [
        '<?xml version="1.0" encoding="UTF-8" standalone="no" ?>\n',
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"\n',
        '"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">\n',
        '<html xmlns="http://www.w3.org/1999/xhtml">\n',
        '<head>\n',
        '  <title>书籍简介</title>\n',
        '  <link rel="stylesheet" type="text/css" href="../Styles/style.css"/>\n',
        '</head>\n',
        '<body>\n',
        f'  <h1>{safe_title}</h1>\n',
    ]
    if safe_vol:
        lines.append(f'  <h2>{safe_vol}</h2>\n')
    if cover_filename:
        lines.append(
            f'  <div class="illus-box"><img alt="Cover" src="../Images/{html.escape(cover_filename, quote=True)}" style="max-height:280px;"/></div>\n'
        )
    lines.append('  <div class="info-box">\n')
    lines.append(f'    <p><strong>作者：</strong>{safe_author}</p>\n')
    if publisher:
        lines.append(f'    <p><strong>文库：</strong>{html.escape(publisher)}</p>\n')
    if status:
        lines.append(f'    <p><strong>状态：</strong>{html.escape(status)}</p>\n')
    if last_updated:
        lines.append(f'    <p><strong>更新：</strong>{html.escape(last_updated)}</p>\n')
    if word_count:
        lines.append(f'    <p><strong>字数：</strong>{html.escape(word_count)}</p>\n')
    if tags:
        tags_html = ''.join(f'<span class="tag">{html.escape(t)}</span>' for t in tags)
        lines.append(f'    <p><strong>标签：</strong>{tags_html}</p>\n')
    lines.append('  </div>\n')

    if description:
        lines.append('  <hr/>\n  <div class="info-box">\n    <p><strong>内容简介：</strong></p>\n')
        for para in description.splitlines():
            p = para.strip()
            if p:
                lines.append(f'    <p style="text-indent:2em;">{html.escape(p)}</p>\n')
        lines.append('  </div>\n')

    lines.extend(['</body>\n', '</html>'])
    return lines


def get_content_html(
    title: str,
    author: str,
    num_chap: int,
    num_img: int = 0,
    img_exist: bool = False,
    *,
    img_files: Optional[List[str]] = None,
    cover_filename: str = '00.jpg',
    book_uuid: Optional[str] = None,
    publisher: str = '',
    tags: Optional[List[str]] = None,
    description: str = '',
    last_updated: str = '',
    series_name: str = '',
    series_index: Optional[int] = None,
    has_info_page: bool = False,
    has_style_css: bool = False,
    epub_version: str = '2',
    color_files: Optional[List[str]] = None,
    color_placement: str = 'before',
    chap_hrefs: Optional[List[str]] = None,
    include_cover: bool = True,
) -> List[str]:
    """Build EPUB 2.0 / 3.0 OPF package document with rich bibliographic metadata."""
    uid = book_uuid or str(uuid.uuid4())
    is_epub3 = str(epub_version) == '3'
    pkg_version = '3.0' if is_epub3 else '2.0'
    safe_title = html.escape(title)
    safe_author = html.escape(author or '未知')
    safe_cover_id = html.escape(f'x{cover_filename}', quote=True) if cover_filename else ''

    resolved_imgs = (
        list(img_files)
        if img_files is not None
        else [f'{str(i).zfill(2)}.jpg' for i in range(num_img)]
    )

    scheme_attr = '' if is_epub3 else ' opf:scheme="UUID"'
    content_htmls = [
        '<?xml version="1.0" encoding="utf-8"?>\n',
        f'<package version="{pkg_version}" unique-identifier="BookId" xmlns="http://www.idpf.org/2007/opf">\n',
        '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">\n',
        f'    <dc:identifier id="BookId"{scheme_attr}>urn:uuid:{html.escape(uid, quote=True)}</dc:identifier>\n',
        '    <dc:language>zh</dc:language>\n',
        f'    <dc:title>{safe_title}</dc:title>\n',
    ]

    if is_epub3:
        content_htmls.append(f'    <dc:creator id="creator">{safe_author}</dc:creator>\n')
        content_htmls.append('    <meta refines="#creator" property="role" scheme="marc:relators">aut</meta>\n')
        modified = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        content_htmls.append(f'    <meta property="dcterms:modified">{modified}</meta>\n')
        if series_name:
            content_htmls.append(f'    <meta property="belongs-to-collection" id="series">{html.escape(series_name)}</meta>\n')
            content_htmls.append('    <meta refines="#series" property="collection-type">series</meta>\n')
            if series_index is not None:
                content_htmls.append(f'    <meta refines="#series" property="group-position">{int(series_index)}</meta>\n')
    else:
        content_htmls.append(
            f'    <dc:creator opf:role="aut" opf:file-as="{html.escape(author or "未知", quote=True)}">{safe_author}</dc:creator>\n'
        )
        if series_name:
            content_htmls.append(f'    <meta name="calibre:series" content="{html.escape(series_name, quote=True)}"/>\n')
        if series_index is not None:
            content_htmls.append(f'    <meta name="calibre:series_index" content="{int(series_index)}"/>\n')

    if publisher:
        content_htmls.append(f'    <dc:publisher>{html.escape(publisher)}</dc:publisher>\n')
    if last_updated:
        content_htmls.append(f'    <dc:date>{html.escape(last_updated)}</dc:date>\n')
    if description:
        content_htmls.append(f'    <dc:description>{html.escape(description)}</dc:description>\n')
    for tag in (tags or []):
        if tag:
            content_htmls.append(f'    <dc:subject>{html.escape(tag)}</dc:subject>\n')
    if cover_filename and cover_filename in resolved_imgs:
        content_htmls.append(f'    <meta name="cover" content="{safe_cover_id}"/>\n')

    content_htmls.extend([
        '  </metadata>\n',
        '  <manifest>\n',
        '    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>\n',
    ])
    if is_epub3:
        content_htmls.append('    <item id="nav.xhtml" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\n')
    if include_cover:
        content_htmls.append('    <item id="cover.xhtml" href="Text/cover.xhtml" media-type="application/xhtml+xml"/>\n')

    if has_style_css:
        content_htmls.append('    <item id="style.css" href="Styles/style.css" media-type="text/css"/>\n')
    if has_info_page:
        content_htmls.append('    <item id="info.xhtml" href="Text/info.xhtml" media-type="application/xhtml+xml"/>\n')

    resolved_color_files = list(color_files) if color_files is not None else (['Text/color.xhtml'] if img_exist else [])
    color_ids: List[str] = []
    for idx, chref in enumerate(resolved_color_files):
        cid = 'xcolor' if len(resolved_color_files) == 1 and chref == 'Text/color.xhtml' else f'xcolor_{idx:03d}'
        color_ids.append(cid)
        content_htmls.append(
            f'    <item id="{cid}" href="{html.escape(chref, quote=True)}" media-type="application/xhtml+xml"/>\n'
        )

    resolved_chap_hrefs = list(chap_hrefs) if chap_hrefs is not None else [f'Text/{str(i).zfill(2)}.xhtml' for i in range(num_chap)]
    chap_ids: List[str] = []
    for chap_no, href in enumerate(resolved_chap_hrefs):
        chap_id = f'x{str(chap_no).zfill(3)}.xhtml' if len(resolved_chap_hrefs) >= 100 else f'x{str(chap_no).zfill(2)}.xhtml'
        chap_ids.append(chap_id)
        content_htmls.append(
            f'    <item id="{chap_id}" href="{html.escape(href, quote=True)}" media-type="application/xhtml+xml"/>\n'
        )

    for img_name in resolved_imgs:
        safe_name = html.escape(img_name, quote=True)
        mime = get_mime_type(img_name)
        props = ' properties="cover-image"' if (is_epub3 and cover_filename and img_name == cover_filename) else ''
        content_htmls.append(
            f'    <item id="x{safe_name}" href="Images/{safe_name}" media-type="{mime}"{props}/>\n'
        )

    content_htmls.extend([
        '  </manifest>\n',
        '  <spine toc="ncx">\n',
    ])
    if include_cover:
        content_htmls.append('    <itemref idref="cover.xhtml"/>\n')
    if has_info_page:
        content_htmls.append('    <itemref idref="info.xhtml"/>\n')
    if color_placement != 'after':
        for cid in color_ids:
            content_htmls.append(f'    <itemref idref="{cid}"/>\n')
    for chap_id in chap_ids:
        content_htmls.append(f'    <itemref idref="{chap_id}"/>\n')
    if color_placement == 'after':
        for cid in color_ids:
            content_htmls.append(f'    <itemref idref="{cid}"/>\n')

    content_htmls.append('  </spine>\n')
    if include_cover:
        content_htmls.extend([
            '  <guide>\n',
            '    <reference type="cover" title="封面" href="Text/cover.xhtml"/>\n',
            '  </guide>\n',
        ])
    content_htmls.append('</package>\n')
    return content_htmls


def render_filename(
    template: str,
    title: str,
    volume: str,
    index: int,
    author: str,
    book_id: str,
) -> str:
    """Render sanitized EPUB filename stem from template variables."""
    tpl = (template or '').strip() or '{title}-{volume}'
    rendered = (
        tpl.replace('{title}', title)
        .replace('{volume}', volume)
        .replace('{index}', str(index))
        .replace('{author}', author)
        .replace('{id}', str(book_id))
    )
    return check_chars(rendered)


def get_container_html() -> List[str]:
    """Build META-INF/container.xml content."""
    return [
        '<?xml version="1.0" encoding="UTF-8"?>\n',
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n',
        '    <rootfiles>\n',
        '        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>\n',
        '   </rootfiles>\n',
        '</container>\n',
    ]


def get_color_html(color_img_files: Union[List[str], int]) -> List[str]:
    """Build valid XHTML 1.1 color illustration page."""
    if isinstance(color_img_files, int):
        filenames = [f'{str(i).zfill(2)}.jpg' for i in range(1, color_img_files)]
    else:
        filenames = list(color_img_files)

    color_htmls = [
        '<?xml version="1.0" encoding="UTF-8" standalone="no" ?>\n',
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"\n',
        '"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">\n',
        '<html xmlns="http://www.w3.org/1999/xhtml">\n',
        '<head>\n',
        '  <title>彩插</title>\n',
        '  <link rel="stylesheet" type="text/css" href="../Styles/style.css"/>\n',
        '  <style type="text/css">body{text-align:center;} img{max-width:100%;height:auto;margin:0.5em 0;}</style>\n',
        '</head>\n',
        '<body>\n',
    ]
    for fname in filenames:
        safe_fname = html.escape(fname, quote=True)
        alt = html.escape(os.path.splitext(fname)[0], quote=True)
        color_htmls.append(f'  <div class="color-page"><img alt="{alt}" src="../Images/{safe_fname}"/></div>\n')
    color_htmls.extend(['</body>\n', '</html>'])
    return color_htmls


def check_chars(win_chars: str) -> str:
    """Sanitize string so it is safe as a cross-platform filename."""
    win_illegal_chars = '?*"<>|:/\\'
    chars = []
    for ch in win_chars or '':
        if ch in win_illegal_chars or ord(ch) < 32:
            chars.append('\u25A0')
        else:
            chars.append(ch)
    sanitized = ''.join(chars).strip().rstrip('. ')
    return sanitized or 'untitled'
