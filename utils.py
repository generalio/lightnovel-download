import html
import io
import os
import re
import uuid
from typing import Dict, List, Optional, Tuple, Union

from PIL import Image

_IMG_TAG_RE = re.compile(r'^\[img:(\d+)\]$')
_BOOK_URL_RE = re.compile(r'(?:/book/|/novel/\d+/)(\d+)')

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
) -> List[str]:
    """Convert chapter plain text with [img:XX] markers into valid XHTML lines."""
    safe_chap_name = html.escape(chap_name)
    text_body = ['<body>\n', f'<h1>{safe_chap_name}</h1>\n']

    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        img_match = _IMG_TAG_RE.match(stripped)
        if img_match:
            img_no = img_match.group(1)
            filename = img_files.get(img_no, f'{img_no}.jpg') if img_files else f'{img_no}.jpg'
            safe_filename = html.escape(filename, quote=True)
            safe_alt = html.escape(img_no, quote=True)
            text_body.append(
                f'  <div class="illus-box"><img alt="{safe_alt}" src="../Images/{safe_filename}"/></div>\n'
            )
        else:
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
) -> List[str]:
    """Build EPUB NCX navigation file."""
    uid = book_uuid or str(uuid.uuid4())
    safe_title = html.escape(title)
    toc_htmls = [
        '<?xml version="1.0" encoding="utf-8"?>\n',
        '<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN"\n',
        '   "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">\n\n',
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n',
        '  <head>\n',
        f'    <meta name="dtb:uid" content="urn:uuid:{html.escape(uid, quote=True)}" />\n',
        '    <meta name="dtb:depth" content="1" />\n',
        '    <meta name="dtb:totalPageCount" content="0" />\n',
        '    <meta name="dtb:maxPageNumber" content="0" />\n',
        '  </head>\n',
        '  <docTitle>\n',
        f'    <text>{safe_title}</text>\n',
        '  </docTitle>\n',
        '  <navMap>\n',
    ]

    nav_entries: List[Tuple[str, str]] = []
    if extra_nav_items:
        nav_entries.extend(extra_nav_items)
    for chap_no, chap_name in enumerate(chap_names):
        src = chap_files[chap_no] if chap_files else f'Text/{str(chap_no).zfill(2)}.xhtml'
        nav_entries.append((chap_name, src))

    for play_order, (label, src) in enumerate(nav_entries, start=1):
        safe_chap = html.escape(label)
        safe_src = html.escape(src, quote=True)
        toc_htmls.extend([
            f'    <navPoint id="navPoint-{play_order}" playOrder="{play_order}">\n',
            '      <navLabel>\n',
            f'        <text>{safe_chap}</text>\n',
            '      </navLabel>\n',
            f'      <content src="{safe_src}"/>\n',
            '    </navPoint>\n',
        ])

    toc_htmls.extend(['  </navMap>\n', '</ncx>'])
    return toc_htmls


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
) -> List[str]:
    """Build EPUB OPF package document with rich bibliographic metadata."""
    uid = book_uuid or str(uuid.uuid4())
    safe_title = html.escape(title)
    safe_author = html.escape(author or '未知')
    safe_cover_id = html.escape(f'x{cover_filename}', quote=True) if cover_filename else ''

    resolved_imgs = (
        list(img_files)
        if img_files is not None
        else [f'{str(i).zfill(2)}.jpg' for i in range(num_img)]
    )

    content_htmls = [
        '<?xml version="1.0" encoding="utf-8"?>\n',
        '<package version="2.0" unique-identifier="BookId" xmlns="http://www.idpf.org/2007/opf">\n',
        '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">\n',
        f'    <dc:identifier id="BookId" opf:scheme="UUID">urn:uuid:{html.escape(uid, quote=True)}</dc:identifier>\n',
        '    <dc:language>zh</dc:language>\n',
        f'    <dc:title>{safe_title}</dc:title>\n',
        f'    <dc:creator opf:role="aut" opf:file-as="{html.escape(author or "未知", quote=True)}">{safe_author}</dc:creator>\n',
    ]
    if publisher:
        content_htmls.append(f'    <dc:publisher>{html.escape(publisher)}</dc:publisher>\n')
    if last_updated:
        content_htmls.append(f'    <dc:date>{html.escape(last_updated)}</dc:date>\n')
    if description:
        content_htmls.append(f'    <dc:description>{html.escape(description)}</dc:description>\n')
    for tag in (tags or []):
        if tag:
            content_htmls.append(f'    <dc:subject>{html.escape(tag)}</dc:subject>\n')
    if series_name:
        content_htmls.append(f'    <meta name="calibre:series" content="{html.escape(series_name, quote=True)}"/>\n')
    if series_index is not None:
        content_htmls.append(f'    <meta name="calibre:series_index" content="{int(series_index)}"/>\n')
    if cover_filename and cover_filename in resolved_imgs:
        content_htmls.append(f'    <meta name="cover" content="{safe_cover_id}"/>\n')

    content_htmls.extend([
        '  </metadata>\n',
        '  <manifest>\n',
        '    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>\n',
        '    <item id="cover.xhtml" href="Text/cover.xhtml" media-type="application/xhtml+xml"/>\n',
    ])

    if has_style_css:
        content_htmls.append('    <item id="style.css" href="Styles/style.css" media-type="text/css"/>\n')
    if has_info_page:
        content_htmls.append('    <item id="info.xhtml" href="Text/info.xhtml" media-type="application/xhtml+xml"/>\n')
    if img_exist:
        content_htmls.append('    <item id="xcolor" href="Text/color.xhtml" media-type="application/xhtml+xml"/>\n')

    for chap_no in range(num_chap):
        chap_id = f'x{str(chap_no).zfill(2)}.xhtml'
        content_htmls.append(
            f'    <item id="{chap_id}" href="Text/{str(chap_no).zfill(2)}.xhtml" media-type="application/xhtml+xml"/>\n'
        )

    for img_name in resolved_imgs:
        safe_name = html.escape(img_name, quote=True)
        mime = get_mime_type(img_name)
        content_htmls.append(
            f'    <item id="x{safe_name}" href="Images/{safe_name}" media-type="{mime}"/>\n'
        )

    content_htmls.extend([
        '  </manifest>\n',
        '  <spine toc="ncx">\n',
        '    <itemref idref="cover.xhtml"/>\n',
    ])

    if has_info_page:
        content_htmls.append('    <itemref idref="info.xhtml"/>\n')
    if img_exist:
        content_htmls.append('    <itemref idref="xcolor"/>\n')

    for chap_no in range(num_chap):
        content_htmls.append(f'    <itemref idref="x{str(chap_no).zfill(2)}.xhtml"/>\n')

    content_htmls.extend([
        '  </spine>\n',
        '  <guide>\n',
        '    <reference type="cover" title="封面" href="Text/cover.xhtml"/>\n',
        '  </guide>\n',
        '</package>\n',
    ])
    return content_htmls


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
