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
from urllib.parse import urljoin
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
    get_style_css,
    get_toc_html,
    guess_image_ext_and_mime,
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

        self.header = {
            'User-Agent': (
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/124.0.0.0 Safari/537.36'
            ),
            'Referer': self.url_head,
        }
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
        self.tags = []
        self.description = ''
        self.cover_url = ''
        self.temp_path = ''
        self.text_path = ''
        self.img_path = ''
        self.style_path = ''
        self.include_info_page = True

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

        last_error = None
        for attempt in range(1, self.max_retries + 1):
            self._check_cancelled()
            try:
                resp = self.session.get(url, timeout=self.timeout)
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

    def write_chapters_html(self):
        """Render shared CSS, info page, body chapter XHTML files, and optional color.xhtml."""
        if self.style_path:
            os.makedirs(self.style_path, exist_ok=True)
            with open(os.path.join(self.style_path, 'style.css'), 'w', encoding='utf-8') as f:
                f.write(get_style_css())

        for text_no, (chap_name, text) in enumerate(self._body_chapters):
            text_html = text2htmls(chap_name, text, img_files=self.img_file_map)
            textfile = os.path.join(self.text_path, f'{str(text_no).zfill(2)}.xhtml')
            with open(textfile, 'w', encoding='utf-8') as f:
                f.writelines(text_html)

        color_filenames = [
            self.img_file_map[img_no]
            for img_no in self._color_img_nos
            if img_no in self.img_file_map
        ]
        self.has_color_page_output = bool(color_filenames)
        if self.has_color_page_output:
            color_html = get_color_html(color_filenames)
            colorfile = os.path.join(self.text_path, 'color.xhtml')
            with open(colorfile, 'w', encoding='utf-8') as f:
                f.writelines(color_html)

        self._chapters_written = True

    def get_cover(self, is_gui=False, signal=None):
        if not self._chapters_written:
            self.write_chapters_html()

        textfile = os.path.join(self.text_path, 'cover.xhtml')
        img_w, img_h = 600, 850
        cover_filename = self.img_file_map.get(self.cover_img_no or '00', '')

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
            safe_title = html.escape(self.title)
            safe_vol = html.escape(self.volume.get("book_name", ""))
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
                title=self.title,
                volume_name=self.volume.get('book_name', ''),
                author=self.author,
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

    def get_toc(self):
        if not self._chapters_written:
            self.write_chapters_html()
        chap_names = [chap_name for chap_name, _ in self._body_chapters]
        extra_nav = [('封面', 'Text/cover.xhtml')]
        if self.include_info_page:
            extra_nav.append(('书籍简介', 'Text/info.xhtml'))
        if self.has_color_page_output:
            extra_nav.append(('彩插', 'Text/color.xhtml'))

        vol_title = f'{self.title}-{self.volume["book_name"]}' if self.volume.get('book_name') else self.title
        toc_htmls = get_toc_html(
            vol_title,
            chap_names,
            book_uuid=self._book_uuid,
            extra_nav_items=extra_nav,
        )
        toc_file = os.path.join(self.temp_path, 'OEBPS', 'toc.ncx')
        with open(toc_file, 'w', encoding='utf-8') as f:
            f.writelines(toc_htmls)

    def get_content(self):
        num_chap = len(self._body_chapters)
        img_files = sorted(os.listdir(self.img_path)) if os.path.isdir(self.img_path) else []
        cover_filename = self.img_file_map.get(self.cover_img_no or '00', '')
        vol_name = self.volume.get('book_name', '')
        full_title = f'{self.title}-{vol_name}' if vol_name else self.title
        series_idx = self.volume_no if isinstance(self.volume_no, int) else None
        content_htmls = get_content_html(
            full_title,
            self.author,
            num_chap,
            img_exist=self.has_color_page_output,
            img_files=img_files,
            cover_filename=cover_filename,
            book_uuid=self._book_uuid,
            publisher=self.publisher,
            tags=self.tags,
            description=self.description,
            last_updated=self.last_updated,
            series_name=self.title,
            series_index=series_idx,
            has_info_page=self.include_info_page,
            has_style_css=True,
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
        epub_name = f'{check_chars(self.title)}-{check_chars(self.volume["book_name"])}.epub'
        epub_file = os.path.join(self.epub_path, epub_name)

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

    def cleanup_temp(self):
        if self.temp_path and os.path.exists(self.temp_path):
            shutil.rmtree(self.temp_path, ignore_errors=True)
