#!/usr/bin/python
# -*- coding:utf-8 -*-

import html
from concurrent.futures import ThreadPoolExecutor, as_completed
import os
import re
import shutil
import threading
import time
import uuid
from urllib.parse import quote_from_bytes, urljoin
import zipfile

from bs4 import BeautifulSoup, Comment, NavigableString, Tag
from PIL import Image
import requests
from rich.progress import track as tqdm

from utils import (
    check_chars,
    extract_book_id,
    get_color_html,
    get_container_html,
    get_content_html,
    get_cover_html,
    get_info_html,
    get_nav_xhtml,
    get_style_css,
    get_toc_html,
    guess_image_ext_and_mime,
    render_filename,
    text2htmls,
)


class DownloadCancelled(Exception):
    """Raised when a download task is cancelled by the user."""


class Editer(object):
    COLOR_CHAP_KEYWORDS = ('插图', '彩页', '插画')
    OFFICIAL_MIRRORS = ('https://www.wenku8.cc', 'https://www.wenku8.net')
    CLOUDFLARE_MARKERS = (
        'used Cloudflare to restrict access',
        'Just a moment...',
        'Attention Required! | Cloudflare',
    )

    def __init__(
        self,
        root_path,
        book_no='0000',
        volume_no=1,
        base_url='https://www.wenku8.cc',
        max_thread_num=8,
        timeout=15,
        max_retries=3,
        cancel_event=None,
        cookie='',
        epub_version='3',
        include_info_page=True,
        include_cover=True,
        split_color_pages=True,
        color_placement='before',
        clean_credits=False,
        text_indent_em=2.0,
        line_height=1.65,
        paragraph_spacing_em=0.5,
        custom_title='',
        custom_author='',
        filename_template='{title}-{volume}',
        cover_file='',
        extra_color_files=None,
    ):
        self.url_head = (base_url or 'https://www.wenku8.cc').strip().rstrip('/')
        if not self.url_head.startswith(('http://', 'https://')):
            self.url_head = f'https://{self.url_head}'

        parsed_id = extract_book_id(str(book_no))
        self.book_no = parsed_id if parsed_id else str(book_no).strip()
        self.volume_no = volume_no
        self.epub_path = root_path or './out'
        self.max_thread_num = max(1, int(max_thread_num))
        self.timeout = timeout
        self.max_retries = max(1, int(max_retries))
        self.cancel_event = cancel_event or threading.Event()
        self.cookie = self._normalize_cookie(cookie or os.environ.get('WENKU8_COOKIE', ''))

        self.header = {
            'User-Agent': (
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/126.0.0.0 Safari/537.36'
            ),
            'Referer': self.url_head,
        }
        if self.cookie:
            self.header['Cookie'] = self.cookie
        self.session = requests.Session()
        self.session.headers.update(self.header)

        self.main_page = f'{self.url_head}/book/{self.book_no}.htm'
        self.cata_page = ''
        self.title = ''
        self.author = ''
        self.publisher = ''
        self.status = ''
        self.last_updated = ''
        self.word_count = ''
        self.popularity = ''
        self.tags = []
        self.description = ''
        self.recommendations = []
        self.cover_url = ''
        self.temp_path = ''
        self.text_path = ''
        self.img_path = ''
        self.style_path = ''

        self.epub_version = str(epub_version) if str(epub_version) in ('2', '3') else '3'
        self.include_info_page = bool(include_info_page)
        self.include_cover = bool(include_cover)
        self.split_color_pages = bool(split_color_pages)
        self.color_placement = color_placement if color_placement in ('before', 'after', 'none') else 'before'
        self.clean_credits = bool(clean_credits)
        self.text_indent_em = float(text_indent_em)
        self.line_height = float(line_height)
        self.paragraph_spacing_em = float(paragraph_spacing_em)
        self.custom_title = (custom_title or '').strip()
        self.custom_author = (custom_author or '').strip()
        self.filename_template = (filename_template or '{title}-{volume}').strip()
        self.cover_file = (cover_file or '').strip()
        self.extra_color_files = list(extra_color_files or [])
        self._color_page_files = []
        self._merged_volume_groups = None
        self._merged_label = ''

        self.color_chap_name = '插图'
        self.color_page_name = '彩页'
        self.is_color_page = False
        self.has_color_page_output = False
        self.has_cover = False
        self.cover_img_no = ''

        self.volume = {'chap_urls': [], 'chap_names': [], 'book_name': ''}
        self.img_url_map = {}
        self.img_file_map = {}
        self.html_buffer = {}
        self._lock = threading.RLock()

        self._info_fetched = False
        self._cata_html = ''
        self._body_chapters = []
        self._body_img_nos = set()
        self._color_img_nos = []
        self._chapters_written = False
        self._book_uuid = str(uuid.uuid4())

    def _check_cancelled(self):
        if self.cancel_event.is_set():
            raise DownloadCancelled('下载任务已取消')

    def _sleep_cancellable(self, seconds):
        if seconds <= 0:
            return
        if self.cancel_event.wait(seconds):
            raise DownloadCancelled('下载任务已取消')

    @staticmethod
    def _normalize_cookie(raw):
        cleaned = (raw or '').strip()
        if cleaned.lower().startswith('cookie:'):
            cleaned = cleaned[7:].strip()
        return cleaned.replace('\r\n', '; ').replace('\n', '; ').strip('"\' ')

    def _set_base_url(self, base_url):
        self.url_head = (base_url or 'https://www.wenku8.net').strip().rstrip('/')
        if not self.url_head.startswith(('http://', 'https://')):
            self.url_head = f'https://{self.url_head}'
        self.main_page = f'{self.url_head}/book/{self.book_no}.htm'
        self.session.headers['Referer'] = self.url_head

    def fetch_book_info(self, force=False):
        """Fetch main book page and catalog page metadata, with automatic mirror fallback."""
        if self._info_fetched and not force:
            return True

        self._check_cancelled()
        if not self.book_no or not self.book_no.isdigit():
            raise ValueError(f'无效的书号：{self.book_no}')

        candidates = [self.url_head]
        if self.url_head in self.OFFICIAL_MIRRORS:
            for mirror in self.OFFICIAL_MIRRORS:
                if mirror not in candidates:
                    candidates.append(mirror)

        last_error = None
        for idx, candidate in enumerate(candidates):
            self._check_cancelled()
            if idx > 0:
                print(f'主站访问受限，自动切换备用域名：{candidate}')
                self._set_base_url(candidate)
            try:
                return self._fetch_book_info_once()
            except DownloadCancelled:
                raise
            except (RuntimeError, requests.RequestException) as exc:
                last_error = exc
                continue

        raise last_error

    def _fetch_book_info_once(self):
        main_html = self.get_html(self.main_page, is_gbk=True)
        soup_main = BeautifulSoup(main_html, 'html.parser')

        cata_link = soup_main.find('a', string=re.compile(r'小说目录'))
        if cata_link and cata_link.get('href'):
            self.cata_page = urljoin(self.main_page, cata_link['href'])
        else:
            match = re.search(r'<a\s+href="(.*?)"[^>]*>\s*小说目录\s*</a>', main_html)
            if not match:
                raise RuntimeError('未能从书籍主页解析出“小说目录”链接，请检查书号是否正确或网站页面是否变更')
            self.cata_page = urljoin(self.main_page, match.group(1))

        self._cata_html = self.get_html(self.cata_page, is_gbk=True)
        soup_cata = BeautifulSoup(self._cata_html, 'html.parser')

        title_el = soup_cata.find('div', {'id': 'title'})
        info_el = soup_cata.find('div', {'id': 'info'})
        if not title_el:
            raise RuntimeError('未能解析书籍标题，书籍可能不存在或页面受限')

        self.title = title_el.get_text(strip=True)
        raw_info = info_el.get_text(strip=True) if info_el else ''
        self.author = re.sub(r'^作者[:：]\s*', '', raw_info).strip() or '未知'
        self._parse_book_page_metadata(soup_main)

        self.cover_url = self._extract_cover_url(soup_main)
        self.temp_path = os.path.join(
            self.epub_path,
            f'temp_{check_chars(self.title)}_{self.volume_no}_{self._book_uuid[:8]}',
        )
        self._info_fetched = True
        return True

    def _parse_book_page_metadata(self, soup_main):
        content_div = soup_main.find('div', {'id': 'content'})
        if not content_div:
            return
        full_text = content_div.get_text('\n', strip=True)
        for line in full_text.splitlines():
            if line.startswith('文库分类：'):
                self.publisher = line.split('：', 1)[1].strip()
            elif line.startswith('文章状态：'):
                self.status = line.split('：', 1)[1].strip()
            elif line.startswith('最后更新：'):
                self.last_updated = line.split('：', 1)[1].strip()
            elif line.startswith('全文长度：'):
                self.word_count = line.split('：', 1)[1].strip()
            elif line.startswith('作品热度：'):
                self.popularity = line.split('：', 1)[1].strip()
            elif line.startswith('作品Tags：'):
                raw_tags = line.split('：', 1)[1].strip()
                self.tags = [t for t in raw_tags.split() if t]

        desc_marker = content_div.find('span', string=re.compile(r'内容简介'))
        if desc_marker:
            desc_parts = []
            for sib in desc_marker.next_siblings:
                if isinstance(sib, Tag) and sib.name == 'span':
                    desc_parts.append(sib.get_text('\n', strip=True))
                    break
            self.description = '\n'.join(p for p in desc_parts if p).strip()

        seen_recs = set()
        self.recommendations = []
        for a in content_div.select('a[href*="/book/"]'):
            rec_id = extract_book_id(a.get('href', ''))
            rec_title = a.get_text(strip=True)
            if rec_id and rec_title and rec_id not in seen_recs:
                seen_recs.add(rec_id)
                self.recommendations.append({'id': rec_id, 'title': rec_title})

    def _extract_cover_url(self, soup_main):
        content_div = soup_main.find('div', {'id': 'content'})
        if content_div:
            for img in content_div.find_all('img'):
                src = (img.get('src') or '').strip()
                if src and ('/image/' in src or 'cover' in src.lower() or '/files/article/' in src):
                    return urljoin(self.main_page, src)
            first_content_img = content_div.find('img')
            if first_content_img and first_content_img.get('src'):
                return urljoin(self.main_page, first_content_img['src'].strip())

        imgs = [img.get('src', '').strip() for img in soup_main.find_all('img') if img.get('src')]
        if len(imgs) > 1:
            return urljoin(self.main_page, imgs[1])
        if imgs:
            return urljoin(self.main_page, imgs[0])
        return ''

    def get_html(self, url, is_gbk=True):
        """Fetch HTML document with polite delay, timeout, bounded retries, and cancellation."""
        self._sleep_cancellable(0.35)
        last_error = None

        for attempt in range(1, self.max_retries + 1):
            self._check_cancelled()
            try:
                resp = self.session.get(url, timeout=self.timeout)
                if is_gbk:
                    resp.encoding = 'gb18030'
                text = resp.text

                if any(marker in text for marker in self.CLOUDFLARE_MARKERS) or resp.status_code == 403:
                    raise RuntimeError(f'访问受限（Cloudflare / HTTP {resp.status_code}）：{url}')

                if resp.status_code >= 400:
                    last_error = RuntimeError(f'HTTP {resp.status_code} 请求失败：{url}')
                    if resp.status_code >= 500 and attempt < self.max_retries:
                        self._sleep_cancellable(1.5 * attempt)
                        continue
                    raise last_error

                return text
            except DownloadCancelled:
                raise
            except requests.RequestException as exc:
                last_error = exc
                if attempt < self.max_retries:
                    self._sleep_cancellable(1.2 * attempt)
                    continue
                raise RuntimeError(f'网络请求失败（{url}）：{exc}') from exc

        raise RuntimeError(f'获取页面失败（{url}）：{last_error}')

    def get_html_img(self, url, is_buffer=False):
        """Download binary image bytes with validation and bounded retries."""
        if is_buffer:
            with self._lock:
                cached = self.html_buffer.get(url)
            if cached is not None:
                return cached

        with self._lock:
            if url in self.html_buffer:
                return self.html_buffer[url]

        candidates = [url]
        if url.startswith('http://'):
            candidates = ['https://' + url[7:], url]

        last_error = None
        for target_url in candidates:
            for attempt in range(1, self.max_retries + 1):
                self._check_cancelled()
                try:
                    resp = self.session.get(target_url, timeout=self.timeout)
                    if resp.status_code != 200 or not resp.content:
                        raise RuntimeError(f'HTTP {resp.status_code}')
                    content_type = (resp.headers.get('Content-Type') or '').lower()
                    if 'text/html' in content_type and not resp.content.startswith((b'\xff\xd8', b'\x89PNG', b'GIF')):
                        raise RuntimeError('返回内容为 HTML 而非图片')
                    with self._lock:
                        self.html_buffer[url] = resp.content
                    return resp.content
                except DownloadCancelled:
                    raise
                except Exception as exc:
                    last_error = exc
                    if attempt < self.max_retries:
                        self._sleep_cancellable(0.8 * attempt)

        raise RuntimeError(f'图片下载失败（{url}）：{last_error}')

    def make_folder(self):
        os.makedirs(self.epub_path, exist_ok=True)
        os.makedirs(self.temp_path, exist_ok=True)

        self.text_path = os.path.join(self.temp_path, 'OEBPS', 'Text')
        os.makedirs(self.text_path, exist_ok=True)

        self.img_path = os.path.join(self.temp_path, 'OEBPS', 'Images')
        os.makedirs(self.img_path, exist_ok=True)

        self.style_path = os.path.join(self.temp_path, 'OEBPS', 'Styles')
        os.makedirs(self.style_path, exist_ok=True)

    def get_index_url(self):
        self.fetch_book_info()
        self.volume = {'chap_urls': [], 'chap_names': [], 'book_name': ''}
        volume_title_list, chap_names_list, chap_urls_list = self.get_chap_list(is_print=False)
        if not volume_title_list:
            print('未获取到任何分卷信息！')
            return False
        if not isinstance(self.volume_no, int) or self.volume_no < 1 or len(volume_title_list) < self.volume_no:
            print(f'输入卷号超出范围（共 {len(volume_title_list)} 卷）！')
            return False
        volume_array = self.volume_no - 1
        self.volume['chap_names'] = chap_names_list[volume_array]
        self.volume['chap_urls'] = chap_urls_list[volume_array]
        self.volume['book_name'] = volume_title_list[volume_array]
        return True

    def get_chap_list(self, is_print=True):
        self.fetch_book_info()
        cata_html = self._cata_html or self.get_html(self.cata_page, is_gbk=True)
        bf = BeautifulSoup(cata_html, 'html.parser')
        chap_table = bf.find('table', {'class': 'css'})
        if not chap_table:
            raise RuntimeError('未能解析小说目录表格')

        volume_title_list = []
        chap_urls_list = []
        chap_names_list = []

        for cell in chap_table.find_all('td'):
            classes = cell.get('class') or []
            if 'vcss' in classes:
                volume_title = cell.get_text(strip=True)
                volume_title_list.append(volume_title)
                chap_urls_list.append([])
                chap_names_list.append([])
            elif 'ccss' in classes and volume_title_list:
                link = cell.find('a', href=True)
                chap_name = (link.get_text(strip=True) if link else cell.get_text(strip=True)).strip('\xa0 ')
                if link and chap_name:
                    chap_names_list[-1].append(chap_name)
                    chap_urls_list[-1].append(urljoin(self.cata_page, link['href']))

        if is_print:
            for volume_no, volume_title in enumerate(volume_title_list):
                print(f'[{volume_no + 1}] {volume_title}')
        return volume_title_list, chap_names_list, chap_urls_list

    def _register_image(self, img_url):
        with self._lock:
            for existing_no, existing_url in self.img_url_map.items():
                if existing_url == img_url:
                    return existing_no
            idx = str(len(self.img_url_map)).zfill(2)
            self.img_url_map[idx] = img_url
            return idx

    def _extract_content_nodes(self, node, page_url, out_parts, img_nos):
        if isinstance(node, Comment):
            return
        if isinstance(node, NavigableString):
            out_parts.append(str(node))
            return
        if not isinstance(node, Tag):
            return

        tag_name = (node.name or '').lower()
        node_id = (node.get('id') or '').lower()
        if tag_name in ('script', 'style') or node_id == 'contentdp':
            return
        if tag_name == 'br':
            out_parts.append('\n')
            return
        if tag_name == 'img':
            src = (node.get('src') or node.get('data-src') or '').strip()
            if src:
                full_url = urljoin(page_url, src)
                img_no = self._register_image(full_url)
                img_nos.add(img_no)
                out_parts.append(f'\n[img:{img_no}]\n')
            return

        is_block = tag_name in ('p', 'div', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6')
        for child in node.children:
            self._extract_content_nodes(child, page_url, out_parts, img_nos)
        if is_block:
            out_parts.append('\n')

    def get_chap_text(self, url, chap_name, is_color=False):
        print(chap_name)
        content_html = self.get_html(url, is_gbk=True)
        bf = BeautifulSoup(content_html, 'html.parser')
        text_with_head = bf.find('div', {'id': 'content'})
        if not text_with_head:
            raise RuntimeError(f'章节“{chap_name}”内容解析失败，未找到正文区域')

        if is_color:
            img_tags = text_with_head.find_all('img')
            color_nos = []
            for img_tag in img_tags:
                src = (img_tag.get('src') or img_tag.get('data-src') or '').strip()
                if not src:
                    continue
                img_url = urljoin(url, src)
                img_no = self._register_image(img_url)
                color_nos.append(img_no)
            return color_nos

        out_parts = []
        inline_imgs = set()
        self._extract_content_nodes(text_with_head, url, out_parts, inline_imgs)
        self._body_img_nos.update(inline_imgs)
        return ''.join(out_parts)

    def check_volume(self, is_gui=False, signal=None, editline=None):
        """Detect whether the volume has an illustration/color chapter and prepare cover mapping."""
        matched_color = None
        for chap_name in self.volume['chap_names']:
            if chap_name.strip() in self.COLOR_CHAP_KEYWORDS:
                matched_color = chap_name
                break

        if matched_color:
            self.color_chap_name = matched_color
            self.is_color_page = True
        else:
            self.is_color_page = False
            print('**************')
            print('提示：本卷没有独立插图页，将使用主页封面作为本卷图书封面')
            print('**************')

    def get_text(self):
        self.make_folder()
        self.img_url_map = {}
        self.img_file_map = {}
        self._body_chapters = []
        self._body_img_nos = set()
        self._color_img_nos = []
        self._chapters_written = False
        self.has_cover = False
        self.cover_img_no = ''
        self.has_color_page_output = False

        chap_pairs = list(zip(self.volume['chap_names'], self.volume['chap_urls']))

        # Process color page first so its first image naturally becomes '00' (volume cover)
        if self.is_color_page:
            for chap_name, chap_url in chap_pairs:
                if chap_name == self.color_chap_name:
                    color_nos = self.get_chap_text(chap_url, chap_name, is_color=True)
                    if color_nos:
                        self.cover_img_no = color_nos[0]
                        self.has_cover = True
                        self._color_img_nos = color_nos[1:]
                    break

        if not self.has_cover and self.cover_url:
            self.cover_img_no = self._register_image(self.cover_url)
            self.has_cover = True

        for chap_name, chap_url in chap_pairs:
            if self.is_color_page and chap_name == self.color_chap_name:
                continue
            text = self.get_chap_text(chap_url, chap_name, is_color=False)
            self._body_chapters.append((chap_name, text))

        if self._color_img_nos:
            self._color_img_nos = [
                img_no for img_no in self._color_img_nos if img_no not in self._body_img_nos
            ]
        self.has_color_page_output = bool(self._color_img_nos)

    def _download_one_image(self, img_no, img_url):
        data = self.get_html_img(img_url)
        ext, _ = guess_image_ext_and_mime(data, img_url)
        filename = f'{img_no}{ext}'
        out_file = os.path.join(self.img_path, filename)
        with open(out_file, 'wb') as f:
            f.write(data)
        return img_no, filename

    def get_image(self, is_gui=False, signal=None):
        total = len(self.img_url_map)
        if total == 0:
            self.write_chapters_html()
            return

        if is_gui and signal is not None:
            signal.emit('start')

        completed_count = 0
        try:
            with ThreadPoolExecutor(max_workers=self.max_thread_num) as pool:
                future_map = {
                    pool.submit(self._download_one_image, img_no, img_url): (img_no, img_url)
                    for img_no, img_url in self.img_url_map.items()
                }
                iterator = as_completed(future_map)
                if not is_gui:
                    iterator = tqdm(iterator, total=total, description='下载插图')

                for future in iterator:
                    self._check_cancelled()
                    img_no, img_url = future_map[future]
                    try:
                        no, filename = future.result()
                        self.img_file_map[no] = filename
                    except DownloadCancelled:
                        raise
                    except Exception as exc:
                        print(f'警告：图片 [{img_no}] 下载失败 ({img_url})：{exc}')
                    completed_count += 1
                    if is_gui and signal is not None:
                        signal.emit(int(100 * completed_count / total))
        finally:
            if is_gui and signal is not None:
                signal.emit('end')

        self.write_chapters_html()

    def _register_local_image(self, local_path):
        with open(local_path, 'rb') as f:
            data = f.read()
        ext, _ = guess_image_ext_and_mime(data, local_path)
        idx = str(len(self.img_file_map) + len(self.img_url_map)).zfill(2)
        while idx in self.img_file_map:
            idx = str(int(idx) + 1).zfill(2)
        filename = f'{idx}{ext}'
        os.makedirs(self.img_path, exist_ok=True)
        with open(os.path.join(self.img_path, filename), 'wb') as out_f:
            out_f.write(data)
        self.img_file_map[idx] = filename
        return idx, filename

    def write_chapters_html(self):
        """Render shared CSS, body chapter XHTML files, and optional color page(s)."""
        if self.style_path:
            os.makedirs(self.style_path, exist_ok=True)
            css = get_style_css(
                text_indent_em=self.text_indent_em,
                line_height=self.line_height,
                paragraph_spacing_em=self.paragraph_spacing_em,
            )
            with open(os.path.join(self.style_path, 'style.css'), 'w', encoding='utf-8') as f:
                f.write(css)

        if self.cover_file and os.path.isfile(self.cover_file):
            cover_idx, _ = self._register_local_image(self.cover_file)
            self.cover_img_no = cover_idx
            self.has_cover = True

        chap_digits = 3 if len(self._body_chapters) >= 100 else 2
        for text_no, (chap_name, text) in enumerate(self._body_chapters):
            text_html = text2htmls(
                chap_name,
                text,
                img_files=self.img_file_map,
                clean_credits=self.clean_credits,
            )
            textfile = os.path.join(self.text_path, f'{str(text_no).zfill(chap_digits)}.xhtml')
            with open(textfile, 'w', encoding='utf-8') as f:
                f.writelines(text_html)

        color_filenames = []
        if self.color_placement != 'none':
            color_filenames = [
                self.img_file_map[img_no]
                for img_no in self._color_img_nos
                if img_no in self.img_file_map
            ]
            for extra_path in self.extra_color_files:
                if os.path.isfile(extra_path):
                    _, fname = self._register_local_image(extra_path)
                    color_filenames.append(fname)

        self._color_page_files = []
        self.has_color_page_output = bool(color_filenames)
        if self.has_color_page_output:
            if self.split_color_pages:
                for idx, fname in enumerate(color_filenames):
                    page_name = f'color_{idx:03d}.xhtml'
                    color_html = get_color_html([fname])
                    with open(os.path.join(self.text_path, page_name), 'w', encoding='utf-8') as f:
                        f.writelines(color_html)
                    self._color_page_files.append(f'Text/{page_name}')
            else:
                color_html = get_color_html(color_filenames)
                with open(os.path.join(self.text_path, 'color.xhtml'), 'w', encoding='utf-8') as f:
                    f.writelines(color_html)
                self._color_page_files.append('Text/color.xhtml')

        self._chapters_written = True

    def get_cover(self, is_gui=False, signal=None):
        if not self._chapters_written:
            self.write_chapters_html()

        eff_title = self.custom_title or self.title
        eff_author = self.custom_author or self.author
        vol_label = self._merged_label or self.volume.get('book_name', '')
        cover_filename = self.img_file_map.get(self.cover_img_no or '00', '')

        if self.include_cover:
            textfile = os.path.join(self.text_path, 'cover.xhtml')
            img_w, img_h = 600, 850
            if cover_filename:
                imgfile = os.path.join(self.img_path, cover_filename)
                try:
                    with Image.open(imgfile) as img:
                        img_w, img_h = img.size
                    if is_gui and signal is not None:
                        signal.emit((imgfile, img_h, img_w))
                except Exception as exc:
                    print(f'读取封面图片尺寸失败：{exc}')
                    print('将使用默认封面尺寸')
            else:
                print('没有封面图片，请自行用第三方EPUB编辑器手动添加封面')

            if cover_filename:
                img_htmls = get_cover_html(img_w, img_h, cover_filename=cover_filename)
            else:
                safe_title = html.escape(eff_title)
                safe_vol = html.escape(vol_label)
                img_htmls = [
                    '<?xml version="1.0" encoding="UTF-8" standalone="no" ?>\n',
                    '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"\n',
                    '"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">\n',
                    '<html xmlns="http://www.w3.org/1999/xhtml">\n',
                    '<head><title>Cover</title></head>\n',
                    f'<body><div style="text-align:center;margin-top:30%;"><h1>{safe_title}</h1><p>{safe_vol}</p></div></body>\n',
                    '</html>',
                ]
            with open(textfile, 'w', encoding='utf-8') as f:
                f.writelines(img_htmls)

        if self.include_info_page:
            info_htmls = get_info_html(
                title=eff_title,
                volume_name=vol_label,
                author=eff_author,
                publisher=self.publisher,
                status=self.status,
                last_updated=self.last_updated,
                word_count=self.word_count,
                tags=self.tags,
                description=self.description,
                cover_filename=cover_filename,
            )
            with open(os.path.join(self.text_path, 'info.xhtml'), 'w', encoding='utf-8') as f:
                f.writelines(info_htmls)

    def _build_nav_lists(self):
        chap_digits = 3 if len(self._body_chapters) >= 100 else 2
        chap_names = [chap_name for chap_name, _ in self._body_chapters]
        chap_hrefs = [f'Text/{str(i).zfill(chap_digits)}.xhtml' for i in range(len(self._body_chapters))]

        front_nav = []
        if self.include_cover:
            front_nav.append(('封面', 'Text/cover.xhtml'))
        if self.include_info_page:
            front_nav.append(('书籍简介', 'Text/info.xhtml'))

        back_nav = []
        if self._color_page_files:
            target_nav = ('彩插', self._color_page_files[0])
            if self.color_placement == 'after':
                back_nav.append(target_nav)
            else:
                front_nav.append(target_nav)

        return chap_names, chap_hrefs, front_nav, back_nav

    def get_toc(self):
        if not self._chapters_written:
            self.write_chapters_html()
        eff_title = self.custom_title or self.title
        vol_label = self._merged_label or self.volume.get('book_name', '')
        vol_title = f'{eff_title}-{vol_label}' if vol_label else eff_title
        chap_names, chap_hrefs, front_nav, back_nav = self._build_nav_lists()

        toc_htmls = get_toc_html(
            vol_title,
            chap_names,
            chap_files=chap_hrefs,
            book_uuid=self._book_uuid,
            extra_nav_items=front_nav,
            volume_groups=self._merged_volume_groups,
            back_nav_items=back_nav,
        )
        toc_file = os.path.join(self.temp_path, 'OEBPS', 'toc.ncx')
        with open(toc_file, 'w', encoding='utf-8') as f:
            f.writelines(toc_htmls)

        if self.epub_version == '3':
            nav_htmls = get_nav_xhtml(
                vol_title,
                chap_names,
                chap_files=chap_hrefs,
                extra_nav_items=front_nav,
                volume_groups=self._merged_volume_groups,
                back_nav_items=back_nav,
            )
            nav_file = os.path.join(self.temp_path, 'OEBPS', 'nav.xhtml')
            with open(nav_file, 'w', encoding='utf-8') as f:
                f.writelines(nav_htmls)

    def get_content(self):
        num_chap = len(self._body_chapters)
        img_files = sorted(os.listdir(self.img_path)) if os.path.isdir(self.img_path) else []
        cover_filename = self.img_file_map.get(self.cover_img_no or '00', '')
        eff_title = self.custom_title or self.title
        eff_author = self.custom_author or self.author
        vol_name = self._merged_label or self.volume.get('book_name', '')
        full_title = f'{eff_title}-{vol_name}' if vol_name else eff_title
        series_idx = None if self._merged_volume_groups else (self.volume_no if isinstance(self.volume_no, int) else None)
        _, chap_hrefs, _, _ = self._build_nav_lists()

        content_htmls = get_content_html(
            full_title,
            eff_author,
            num_chap,
            img_exist=self.has_color_page_output,
            img_files=img_files,
            cover_filename=cover_filename,
            book_uuid=self._book_uuid,
            publisher=self.publisher,
            tags=self.tags,
            description=self.description,
            last_updated=self.last_updated,
            series_name=eff_title,
            series_index=series_idx,
            has_info_page=self.include_info_page,
            has_style_css=True,
            epub_version=self.epub_version,
            color_files=self._color_page_files,
            color_placement=self.color_placement,
            chap_hrefs=chap_hrefs,
            include_cover=self.include_cover,
        )
        opf_file = os.path.join(self.temp_path, 'OEBPS', 'content.opf')
        with open(opf_file, 'w', encoding='utf-8') as f:
            f.writelines(content_htmls)

    def get_epub_head(self):
        mimetype_file = os.path.join(self.temp_path, 'mimetype')
        with open(mimetype_file, 'w', encoding='utf-8') as f:
            f.write('application/epub+zip')

        metainf_folder = os.path.join(self.temp_path, 'META-INF')
        os.makedirs(metainf_folder, exist_ok=True)
        container = os.path.join(metainf_folder, 'container.xml')
        with open(container, 'w', encoding='utf-8') as f:
            f.writelines(get_container_html())

    def get_epub(self):
        os.makedirs(self.epub_path, exist_ok=True)
        eff_title = self.custom_title or self.title
        eff_author = self.custom_author or self.author
        vol_label = self._merged_label or self.volume.get('book_name', '')
        vol_idx = self.volume_no if isinstance(self.volume_no, int) else 1
        stem = render_filename(
            self.filename_template,
            title=eff_title,
            volume=vol_label,
            index=vol_idx,
            author=eff_author,
            book_id=self.book_no,
        )
        epub_file = os.path.join(self.epub_path, f'{stem}.epub')

        mimetype_file = os.path.join(self.temp_path, 'mimetype')
        with zipfile.ZipFile(epub_file, 'w', zipfile.ZIP_DEFLATED) as zf:
            # Per EPUB specification, mimetype must be the first entry and stored uncompressed
            if os.path.exists(mimetype_file):
                zf.write(mimetype_file, 'mimetype', compress_type=zipfile.ZIP_STORED)

            file_entries = []
            for dirpath, _, filenames in os.walk(self.temp_path):
                rel_dir = os.path.relpath(dirpath, self.temp_path)
                for filename in filenames:
                    if rel_dir == '.' and filename == 'mimetype':
                        continue
                    arc_name = filename if rel_dir == '.' else os.path.join(rel_dir, filename)
                    arc_name = arc_name.replace(os.sep, '/')
                    file_entries.append((os.path.join(dirpath, filename), arc_name))

            for full_path, arc_name in sorted(file_entries, key=lambda item: item[1]):
                zf.write(full_path, arc_name, compress_type=zipfile.ZIP_DEFLATED)

        self.cleanup_temp()
        return epub_file

    def download_merged_volumes(self, volume_nos):
        """Fetch multiple volumes and assemble them into one EPUB with a 2-level nested TOC."""
        self.fetch_book_info()
        volume_titles, chap_names_list, chap_urls_list = self.get_chap_list(is_print=False)
        if not volume_titles:
            raise RuntimeError('未获取到任何分卷信息')

        valid_nos = [v for v in volume_nos if 1 <= v <= len(volume_titles)]
        if not valid_nos:
            raise ValueError(f'卷号超出范围（共 {len(volume_titles)} 卷）')

        self._merged_label = f'合集({len(valid_nos)}卷)'
        self.temp_path = os.path.join(
            self.epub_path,
            f'temp_{check_chars(self.title)}_merged_{self._book_uuid[:8]}',
        )
        self.make_folder()
        self.img_url_map = {}
        self.img_file_map = {}
        self._body_chapters = []
        self._body_img_nos = set()
        self._color_img_nos = []
        self._chapters_written = False
        self.has_cover = False
        self.cover_img_no = ''

        raw_groups = []
        for vol_no in valid_nos:
            self._check_cancelled()
            arr_idx = vol_no - 1
            vol_title = volume_titles[arr_idx]
            print(f'正在抓取合集分卷 [{vol_no}] {vol_title} ...')
            pairs = list(zip(chap_names_list[arr_idx], chap_urls_list[arr_idx]))

            for cname, curl in pairs:
                if cname.strip() in self.COLOR_CHAP_KEYWORDS:
                    color_nos = self.get_chap_text(curl, cname, is_color=True)
                    if color_nos and not self.has_cover:
                        self.cover_img_no = color_nos[0]
                        self.has_cover = True
                        self._color_img_nos.extend(color_nos[1:])
                    else:
                        self._color_img_nos.extend(color_nos)

            vol_chap_indices = []
            for cname, curl in pairs:
                if cname.strip() in self.COLOR_CHAP_KEYWORDS:
                    continue
                text = self.get_chap_text(curl, cname, is_color=False)
                chap_idx = len(self._body_chapters)
                self._body_chapters.append((cname, text))
                vol_chap_indices.append((chap_idx, cname))
            raw_groups.append((vol_title, vol_chap_indices))

        if not self.has_cover and self.cover_url:
            self.cover_img_no = self._register_image(self.cover_url)
            self.has_cover = True

        if self._color_img_nos:
            seen = set()
            deduped = []
            for img_no in self._color_img_nos:
                if img_no not in self._body_img_nos and img_no not in seen:
                    seen.add(img_no)
                    deduped.append(img_no)
            self._color_img_nos = deduped

        chap_digits = 3 if len(self._body_chapters) >= 100 else 2
        self._merged_volume_groups = [
            (
                vtitle,
                [(cname, f'Text/{str(cidx).zfill(chap_digits)}.xhtml') for cidx, cname in citems],
            )
            for vtitle, citems in raw_groups
        ]

        print('正在下载插图.....................................')
        self.get_image(is_gui=False)
        print('正在编辑元数据....')
        self.get_cover(is_gui=False)
        self.get_toc()
        self.get_content()
        self.get_epub_head()
        print('正在生成合集电子书....')
        return self.get_epub()

    @classmethod
    def _encode_gbk_query(cls, text):
        return quote_from_bytes(text.encode('gb18030', errors='ignore'))

    @classmethod
    def _parse_book_cards(cls, html_text):
        soup = BeautifulSoup(html_text, 'html.parser')
        results = []
        for block in soup.select('div#content div[style*="width:373px"]'):
            link = block.select_one('b a[href*="/book/"]') or block.select_one('a[href*="/book/"]')
            if not link:
                continue
            bid = extract_book_id(link.get('href', ''))
            title = link.get_text(strip=True)
            if not bid or not title:
                continue
            info_lines = [ln.strip() for ln in block.get_text('\n', strip=True).splitlines() if ln.strip()]
            author = category = updated = word_count = status = summary = ''
            tags = []
            for ln in info_lines:
                if ln.startswith('作者:'):
                    parts = ln.split('/')
                    author = parts[0].replace('作者:', '').strip()
                    if len(parts) > 1:
                        category = parts[1].replace('分类:', '').strip()
                elif ln.startswith('更新:'):
                    parts = ln.split('/')
                    updated = parts[0].replace('更新:', '').strip()
                    if len(parts) > 1:
                        word_count = parts[1].replace('字数:', '').strip()
                    if len(parts) > 2:
                        status = parts[2].strip()
                elif ln.startswith('Tags:'):
                    tags = [t for t in ln.replace('Tags:', '').split() if t]
                elif ln.startswith('简介:'):
                    summary = ln.replace('简介:', '').strip()
            results.append({
                'id': bid,
                'title': title,
                'author': author,
                'category': category,
                'updated': updated,
                'word_count': word_count,
                'status': status,
                'tags': tags,
                'summary': summary,
            })
        return results

    def search_books(self, query, scope='title'):
        q = (query or '').strip()
        if not q:
            return []
        encoded = self._encode_gbk_query(q)
        if scope == 'author':
            url = f'{self.url_head}/modules/article/authorarticle.php?author={encoded}'
        else:
            url = f'{self.url_head}/modules/article/search.php?searchtype=articlename&searchkey={encoded}'
        page_html = self.get_html(url, is_gbk=True)
        if page_html.strip() == 'Welcome' or '本站正式关闭' in page_html:
            raise RuntimeError('按书名全站搜索需要登录 Cookie，请使用 --cookie 或 WENKU8_COOKIE 环境变量（按作者搜索免登录可用）')
        cards = self._parse_book_cards(page_html)
        if cards:
            return cards
        soup = BeautifulSoup(page_html, 'html.parser')
        cata_a = soup.find('a', string=re.compile(r'小说目录'))
        if cata_a and cata_a.get('href'):
            bid = extract_book_id(cata_a['href'])
            title_b = soup.select_one('#content table b')
            return [{'id': bid, 'title': title_b.get_text(strip=True) if title_b else bid, 'author': '', 'category': '', 'updated': '', 'word_count': '', 'status': '', 'tags': [], 'summary': ''}]
        return []

    def fetch_toplist(self, sort='allvisit'):
        sort_paths = {
            'allvisit': '/modules/article/toplist.php?sort=allvisit',
            'lastupdate': '/modules/article/toplist.php?sort=lastupdate',
            'allvote': '/modules/article/toplist.php?sort=allvote',
            'monthvisit': '/modules/article/toplist.php?sort=monthvisit',
            'completed': '/modules/article/articlelist.php?fullflag=1',
            'anime': '/modules/article/toplist.php?sort=anime',
        }
        path = sort_paths.get(sort, sort_paths['allvisit'])
        url = f'{self.url_head}{path}'
        page_html = self.get_html(url, is_gbk=True)
        if '本站正式关闭' in page_html:
            raise RuntimeError('全站榜单需要登录 Cookie，请通过 --cookie 或 WENKU8_COOKIE 提供 wenku8 Cookie')
        return self._parse_book_cards(page_html)

    def fetch_reviews(self):
        url = f'{self.url_head}/modules/article/reviews.php?aid={self.book_no}'
        page_html = self.get_html(url, is_gbk=True)
        soup = BeautifulSoup(page_html, 'html.parser')
        reviews = []
        for row in soup.select('table.grid tr'):
            cells = row.find_all('td', recursive=False)
            if len(cells) < 4:
                continue
            link = cells[0].find('a', href=True)
            title = (link.get_text(strip=True) if link else cells[0].get_text(strip=True)).strip()
            href = link['href'] if link else ''
            rid_match = re.search(r'rid=(\d+)', href)
            if title:
                reviews.append({
                    'rid': rid_match.group(1) if rid_match else '',
                    'title': title,
                    'stats': cells[1].get_text(strip=True),
                    'author': cells[2].get_text(strip=True),
                    'time': cells[3].get_text(strip=True),
                    'url': urljoin(url, href),
                })
        return reviews

    def fetch_review_thread(self, rid_or_url):
        if str(rid_or_url).isdigit():
            url = f'{self.url_head}/modules/article/reviewshow.php?rid={rid_or_url}'
        else:
            url = urljoin(self.url_head, str(rid_or_url))
        page_html = self.get_html(url, is_gbk=True)
        soup = BeautifulSoup(page_html, 'html.parser')
        posts = []
        for table in soup.select('#content table.grid'):
            if table.find('caption') or table.find(['textarea', 'form']):
                continue
            odd = table.find('td', class_='odd')
            even = table.find('td', class_='even')
            if not odd or not even:
                continue
            if not (even.select_one('a[href*="#yid"]') or odd.select_one('a[href*="userpage.php"]')):
                continue

            author_el = odd.select_one('strong a') or odd.find('strong')
            author = author_el.get_text(strip=True) if author_el else '匿名书友'
            right_div = even.select_one('div[style*="float:right"]')
            right_text = right_div.get_text(' ', strip=True) if right_div else ''
            floor_match = re.search(r'(\d+)#', right_text)
            floor = int(floor_match.group(1)) if floor_match else len(posts) + 1
            time_text = re.sub(r'\|\s*\d+#.*', '', right_text).strip()

            body_divs = even.find_all('div', recursive=False)
            body_el = body_divs[-1] if body_divs else even
            for bad in body_el.find_all(['script', 'style', 'textarea', 'form', 'input']):
                bad.decompose()
            content = body_el.get_text('\n', strip=True)
            if not content:
                continue

            reply_to_match = re.search(r'(?:回复|Re:|@|引用)\s*(\d+)\s*(?:#|楼)', content, re.I)
            reply_to_floor = int(reply_to_match.group(1)) if reply_to_match else None
            if reply_to_floor == floor:
                reply_to_floor = None

            posts.append({
                'floor': floor,
                'author': author,
                'time': time_text,
                'content': content,
                'reply_to_floor': reply_to_floor,
            })
        return posts

    def cleanup_temp(self):
        if self.temp_path and os.path.exists(self.temp_path):
            shutil.rmtree(self.temp_path, ignore_errors=True)
