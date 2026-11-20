import argparse
from typing import List, Optional

from rich.console import Console
from rich.panel import Panel
from rich.table import Table

from Editer import DownloadCancelled, Editer
from utils import extract_book_id

console = Console()


def parse_args():
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(description='轻小说文库 (wenku8) CLI 下载与 EPUB 拼装工具')
    parser.add_argument('--book_no', default='', type=str, help='书籍编号或完整书籍网址')
    parser.add_argument(
        '--volume_no',
        default='',
        type=str,
        help='卷号（留空查询目录；支持 2、1-3、1,2,3、all）',
    )
    parser.add_argument('--info', action='store_true', help='仅查看书籍完整元信息、简介、推荐与分卷目录')
    parser.add_argument('--search', default='', type=str, help='搜索关键字（配合 --search_type 使用）')
    parser.add_argument('--search_type', default='author', choices=['title', 'author'], help='搜索模式：author（免登录）或 title（需 Cookie）')
    parser.add_argument(
        '--toplist',
        default='',
        choices=['', 'allvisit', 'lastupdate', 'allvote', 'monthvisit', 'completed', 'anime'],
        help='查看文库榜单（需 Cookie）',
    )
    parser.add_argument('--reviews', action='store_true', help='查看指定书籍的书评/吐槽列表')
    parser.add_argument('--review_id', default='', type=str, help='查看指定书评帖（rid）的完整楼层与楼中楼回复')
    parser.add_argument('--read', default='', type=str, help='终端阅读指定章节，格式：<卷号>:<章序号>，如 1:1')

    # EPUB assembly options
    parser.add_argument('--merge', action='store_true', help='将所选多卷合并为单本带二级目录的合集 EPUB')
    parser.add_argument('--epub_version', default='3', choices=['2', '3'], help='EPUB 规范版本（默认 3，兼容 2）')
    parser.add_argument('--no_info', action='store_true', help='不生成书籍简介扉页 (info.xhtml)')
    parser.add_argument('--no_cover', action='store_true', help='不包含封面页')
    parser.add_argument('--no_color', action='store_true', help='忽略彩插页')
    parser.add_argument('--single_color_page', action='store_true', help='彩插合并为单页拼接（默认每图一页）')
    parser.add_argument('--color_after', action='store_true', help='将彩插置于正文之后（默认正文前）')
    parser.add_argument('--clean_credits', action='store_true', help='清理章节开头录入组/图源声明行')
    parser.add_argument('--indent', default=2.0, type=float, help='段首缩进 em（默认 2.0）')
    parser.add_argument('--line_height', default=1.65, type=float, help='正文行高（默认 1.65）')
    parser.add_argument('--para_spacing', default=0.5, type=float, help='段落间距 em（默认 0.5）')
    parser.add_argument('--title', default='', type=str, help='自定义 EPUB 书名')
    parser.add_argument('--author', default='', type=str, help='自定义 EPUB 作者')
    parser.add_argument('--filename_template', default='{title}-{volume}', type=str, help='输出文件名模板')
    parser.add_argument('--cover_file', default='', type=str, help='本地自定义封面图片路径')
    parser.add_argument('--extra_color', nargs='*', default=[], help='额外追加本地彩页图片路径列表')

    # Network & output
    parser.add_argument('--out_dir', default='./out', type=str, help='EPUB 输出目录')
    parser.add_argument('--base_url', default='https://www.wenku8.cc', type=str, help='站点域名或镜像地址')
    parser.add_argument('--cookie', default='', type=str, help='wenku8 Cookie（或通过 WENKU8_COOKIE 环境变量传入）')
    parser.add_argument('--threads', default=8, type=int, help='图片下载并发线程数')
    parser.add_argument('--no_input', action='store_true', help='非交互模式，直接按参数执行')
    return parser.parse_args()


def parse_volume_spec(volume_no: str) -> Optional[List[int]]:
    """Parse volume specification string into ordered unique 1-based volume indices."""
    spec = (volume_no or '').strip()
    if not spec:
        return None

    if '-' in spec:
        parts = [p.strip() for p in spec.split('-')]
        if len(parts) != 2 or not parts[0].isdigit() or not parts[1].isdigit():
            raise ValueError('范围格式错误，示例：1-3')
        start, end = int(parts[0]), int(parts[1])
        if start <= 0 or start > end:
            raise ValueError('起始卷号必须大于 0 且不能大于结束卷号')
        return list(range(start, end + 1))

    if ',' in spec or '，' in spec:
        normalized = spec.replace('，', ',')
        parts = [p.strip() for p in normalized.split(',') if p.strip()]
        if not parts or not all(p.isdigit() and int(p) > 0 for p in parts):
            raise ValueError('列表格式错误，示例：1,2,3')
        seen = set()
        result = []
        for p in parts:
            num = int(p)
            if num not in seen:
                seen.add(num)
                result.append(num)
        return result

    if spec.isdigit() and int(spec) > 0:
        return [int(spec)]

    raise ValueError('请检查卷号输入是否完整正确！')


def _make_editer(root_path='./out', book_no='0000', volume_no=1, args=None, base_url='https://www.wenku8.cc', max_thread_num=8, cancel_event=None):
    if args is not None:
        return Editer(
            root_path=root_path,
            book_no=book_no,
            volume_no=volume_no,
            base_url=args.base_url,
            max_thread_num=args.threads,
            cancel_event=cancel_event,
            cookie=args.cookie,
            epub_version=args.epub_version,
            include_info_page=not args.no_info,
            include_cover=not args.no_cover,
            split_color_pages=not args.single_color_page,
            color_placement='none' if args.no_color else ('after' if args.color_after else 'before'),
            clean_credits=args.clean_credits,
            text_indent_em=args.indent,
            line_height=args.line_height,
            paragraph_spacing_em=args.para_spacing,
            custom_title=args.title,
            custom_author=args.author,
            filename_template=args.filename_template,
            cover_file=args.cover_file,
            extra_color_files=args.extra_color,
        )
    return Editer(
        root_path=root_path,
        book_no=book_no,
        volume_no=volume_no,
        base_url=base_url,
        max_thread_num=max_thread_num,
        cancel_event=cancel_event,
    )


def show_book_info(book_no: str, base_url: str = 'https://www.wenku8.cc', cookie: str = ''):
    editer = Editer(root_path='./out', book_no=book_no, base_url=base_url, cookie=cookie)
    editer.fetch_book_info()
    volume_titles, chap_names_list, _ = editer.get_chap_list(is_print=False)

    meta_lines = [
        f'[bold]作者：[/bold]{editer.author}',
        f'[bold]文库：[/bold]{editer.publisher or "未知"}  |  [bold]状态：[/bold]{editer.status or "未知"}  |  [bold]字数：[/bold]{editer.word_count or "未知"}',
        f'[bold]更新：[/bold]{editer.last_updated or "未知"}  |  [bold]来源：[/bold]{editer.url_head}',
    ]
    if editer.tags:
        meta_lines.append(f'[bold]标签：[/bold]{" / ".join(editer.tags)}')
    if editer.description:
        meta_lines.append(f'\n[bold]简介：[/bold]\n{editer.description}')
    console.print(Panel('\n'.join(meta_lines), title=f'[cyan]《{editer.title}》 (#{editer.book_no})[/cyan]', expand=False))

    table = Table(title=f'分卷目录（共 {len(volume_titles)} 卷）')
    table.add_column('卷号', justify='right', style='cyan')
    table.add_column('卷名', style='bold')
    table.add_column('章节数', justify='right')
    for idx, (vtitle, chaps) in enumerate(zip(volume_titles, chap_names_list), start=1):
        table.add_row(str(idx), vtitle, str(len(chaps)))
    console.print(table)

    if editer.recommendations:
        rec_text = '、'.join(f'{r["title"]}(#{r["id"]})' for r in editer.recommendations[:8])
        console.print(f'[dim]同分类推荐：{rec_text}[/dim]')
    return volume_titles


def print_book_cards(items, title='搜索结果'):
    if not items:
        console.print('[yellow]未查询到相关书籍。[/yellow]')
        return
    table = Table(title=title)
    table.add_column('书号', style='cyan', justify='right')
    table.add_column('书名', style='bold')
    table.add_column('作者')
    table.add_column('文库')
    table.add_column('状态')
    table.add_column('字数 / 更新')
    for it in items:
        stat = f'{it["word_count"]} {it["updated"]}'.strip()
        table.add_row(it['id'], it['title'], it['author'], it['category'], it['status'], stat)
    console.print(table)


def show_reviews(book_no: str, base_url: str = 'https://www.wenku8.cc', cookie: str = ''):
    editer = Editer(root_path='./out', book_no=book_no, base_url=base_url, cookie=cookie)
    revs = editer.fetch_reviews()
    if not revs:
        console.print('[yellow]暂无书评。[/yellow]')
        return
    table = Table(title=f'书号 #{editer.book_no} 书评列表')
    table.add_column('帖子ID', style='cyan', justify='right')
    table.add_column('主题', style='bold')
    table.add_column('作者')
    table.add_column('回复/查看', justify='right')
    table.add_column('时间')
    for r in revs[:30]:
        table.add_row(r['rid'], r['title'], r['author'], r['stats'], r['time'])
    console.print(table)
    console.print('[dim]提示：使用 --review_id <帖子ID> 可查看楼层与楼中楼回复[/dim]')


def show_review_thread(rid: str, base_url: str = 'https://www.wenku8.cc', cookie: str = ''):
    editer = Editer(root_path='./out', book_no='0000', base_url=base_url, cookie=cookie)
    posts = editer.fetch_review_thread(rid)
    if not posts:
        console.print('[yellow]未获取到帖子楼层内容。[/yellow]')
        return
    for p in posts:
        indent = '    ↳ ' if p['reply_to_floor'] else ''
        reply_tag = f' [回复 {p["reply_to_floor"]}#]' if p['reply_to_floor'] else ''
        console.print(f'{indent}[cyan]{p["floor"]}#[/cyan] [bold]{p["author"]}[/bold]{reply_tag} [dim]({p["time"]})[/dim]')
        for ln in p['content'].splitlines():
            console.print(f'{indent}  {ln}')
        console.print()


def read_chapter_cli(book_no: str, vol_chap_spec: str, base_url: str = 'https://www.wenku8.cc', cookie: str = ''):
    parts = [p.strip() for p in vol_chap_spec.split(':')]
    if len(parts) != 2 or not parts[0].isdigit() or not parts[1].isdigit():
        raise ValueError('章节格式错误，示例：--read 1:2')
    v_idx, c_idx = int(parts[0]), int(parts[1])
    editer = Editer(root_path='./out', book_no=book_no, volume_no=v_idx, base_url=base_url, cookie=cookie)
    if not editer.get_index_url():
        return
    chaps = list(zip(editer.volume['chap_names'], editer.volume['chap_urls']))
    if c_idx < 1 or c_idx > len(chaps):
        raise ValueError(f'章节序号超出范围（该卷共 {len(chaps)} 章）')
    cname, curl = chaps[c_idx - 1]
    is_color = cname.strip() in editer.COLOR_CHAP_KEYWORDS
    res = editer.get_chap_text(curl, cname, is_color=is_color)
    console.rule(f'[bold]{editer.title} · {editer.volume["book_name"]} · {cname}[/bold]')
    if is_color:
        for i, no in enumerate(res, start=1):
            console.print(f'[插图 {i}] {editer.img_url_map.get(no, "")}')
    else:
        for ln in res.splitlines():
            s = ln.strip()
            if s:
                console.print(f'　　{s}')


def query_chaps(
    book_no: str,
    root_path: str = './out',
    base_url: str = 'https://www.wenku8.cc',
    cancel_event=None,
    cookie: str = '',
):
    print('未输入卷号，将返回书籍目录信息......')
    editer = Editer(
        root_path=root_path,
        book_no=book_no,
        base_url=base_url,
        cancel_event=cancel_event,
        cookie=cookie,
    )
    editer.fetch_book_info()
    print('*******************************')
    print(f'书名：{editer.title}')
    print(f'作者：{editer.author}')
    if editer.publisher or editer.status:
        print(f'分类：{editer.publisher} | 状态：{editer.status} | 字数：{editer.word_count}')
    if editer.tags:
        print(f'标签：{" ".join(editer.tags)}')
    print('*******************************')
    volume_titles, _, _ = editer.get_chap_list()
    print('*******************************')
    print(f'共 {len(volume_titles)} 卷。请输入需要下载的卷号（例如：2、1-3、1,2,3 或 all）')
    return volume_titles


def download_single_volume(
    root_path,
    book_no,
    volume_no,
    is_gui=False,
    hang_signal=None,
    progressring_signal=None,
    cover_signal=None,
    edit_line_hang=None,
    base_url='https://www.wenku8.cc',
    max_thread_num=8,
    cancel_event=None,
    args=None,
):
    editer = _make_editer(
        root_path=root_path,
        book_no=book_no,
        volume_no=volume_no,
        args=args,
        base_url=base_url,
        max_thread_num=max_thread_num,
        cancel_event=cancel_event,
    )
    try:
        print(f'正在获取书籍与第 [{volume_no}] 卷信息....')
        success = editer.get_index_url()
        if not success:
            print('书籍信息获取失败')
            return None

        print(f'{editer.title} - {editer.volume["book_name"]}（{editer.author}）')
        print('****************************')
        editer.check_volume(is_gui=is_gui, signal=hang_signal, editline=edit_line_hang)

        print('正在下载文本....')
        print('*********************')
        editer.get_text()
        print('*********************')

        print('正在下载插图.....................................')
        editer.get_image(is_gui=is_gui, signal=progressring_signal)

        print('正在编辑元数据....')
        editer.get_cover(is_gui=is_gui, signal=cover_signal)
        editer.get_toc()
        editer.get_content()
        editer.get_epub_head()

        print('正在生成电子书....')
        epub_file = editer.get_epub()
        print('生成成功！', f'电子书路径【{epub_file}】')
        return epub_file
    finally:
        editer.cleanup_temp()


def downloader_router(
    root_path,
    book_no,
    volume_no,
    is_gui=False,
    hang_signal=None,
    progressring_signal=None,
    cover_signal=None,
    edit_line_hang=None,
    base_url='https://www.wenku8.cc',
    max_thread_num=8,
    cancel_event=None,
    args=None,
):
    book_id = extract_book_id(str(book_no))
    if not book_id:
        print('请检查书号或书籍网址是否完整正确！')
        return []

    raw_vol = str(volume_no).strip() if volume_no is not None else ''
    cookie = args.cookie if args is not None else ''
    resolved_base = args.base_url if args is not None else base_url

    if raw_vol == '':
        query_chaps(book_id, root_path=root_path, base_url=resolved_base, cancel_event=cancel_event, cookie=cookie)
        return []

    if raw_vol.lower() in ('all', '*'):
        volume_titles = query_chaps(
            book_id,
            root_path=root_path,
            base_url=resolved_base,
            cancel_event=cancel_event,
            cookie=cookie,
        )
        if not volume_titles:
            return []
        volume_no_list = list(range(1, len(volume_titles) + 1))
    else:
        try:
            volume_no_list = parse_volume_spec(raw_vol) or []
        except ValueError as exc:
            print(str(exc))
            return []

    if args is not None and args.merge and len(volume_no_list) > 1:
        editer = _make_editer(
            root_path=root_path,
            book_no=book_id,
            volume_no=volume_no_list[0],
            args=args,
            cancel_event=cancel_event,
        )
        try:
            epub_file = editer.download_merged_volumes(volume_no_list)
            print('合集生成成功！', f'电子书路径【{epub_file}】')
            return [epub_file]
        finally:
            editer.cleanup_temp()

    output_files = []
    for vol_no in volume_no_list:
        if cancel_event is not None and cancel_event.is_set():
            raise DownloadCancelled('下载任务已取消')
        epub_file = download_single_volume(
            root_path,
            book_id,
            vol_no,
            is_gui=is_gui,
            hang_signal=hang_signal,
            progressring_signal=progressring_signal,
            cover_signal=cover_signal,
            edit_line_hang=edit_line_hang,
            base_url=resolved_base,
            max_thread_num=max_thread_num,
            cancel_event=cancel_event,
            args=args,
        )
        if epub_file:
            output_files.append(epub_file)

    if len(volume_no_list) > 1 and output_files:
        print(f'所有下载任务完成！共生成 {len(output_files)} 本 EPUB。')
    return output_files


def run_cli_from_args(args):
    if args.search:
        editer = Editer(root_path=args.out_dir, base_url=args.base_url, cookie=args.cookie)
        items = editer.search_books(args.search, scope=args.search_type)
        print_book_cards(items, title=f'搜索结果：{args.search}')
        return
    if args.toplist:
        editer = Editer(root_path=args.out_dir, base_url=args.base_url, cookie=args.cookie)
        items = editer.fetch_toplist(sort=args.toplist)
        print_book_cards(items, title=f'榜单：{args.toplist}')
        return
    if args.review_id:
        show_review_thread(args.review_id, base_url=args.base_url, cookie=args.cookie)
        return
    if args.reviews:
        bid = extract_book_id(args.book_no)
        if not bid:
            raise ValueError('查看书评请通过 --book_no 指定有效书号')
        show_reviews(bid, base_url=args.base_url, cookie=args.cookie)
        return
    if args.read:
        bid = extract_book_id(args.book_no)
        if not bid:
            raise ValueError('阅读章节请通过 --book_no 指定有效书号')
        read_chapter_cli(bid, args.read, base_url=args.base_url, cookie=args.cookie)
        return
    if args.info:
        bid = extract_book_id(args.book_no)
        if not bid:
            raise ValueError('查看书籍详情请通过 --book_no 指定有效书号')
        show_book_info(bid, base_url=args.base_url, cookie=args.cookie)
        return

    downloader_router(
        root_path=args.out_dir,
        book_no=args.book_no,
        volume_no=args.volume_no,
        base_url=args.base_url,
        max_thread_num=args.threads,
        args=args,
    )


def interactive_loop(args):
    console.print(Panel(
        '直接输入书号/网址下载，或使用快捷命令：\n'
        '  [cyan]info <书号>[/cyan]       查看书籍详情与目录\n'
        '  [cyan]search <书名>[/cyan]     按书名搜索（需 Cookie）\n'
        '  [cyan]author <作者>[/cyan]     按作者搜索（免登录）\n'
        '  [cyan]toplist [sort][/cyan]    查看榜单 (allvisit/lastupdate/completed...)\n'
        '  [cyan]reviews <书号>[/cyan]    查看本书吐槽/书评\n'
        '  [cyan]thread <帖子ID>[/cyan]   查看书评楼层与楼中楼\n'
        '  [cyan]read <书号> <卷:章>[/cyan] 终端阅读正文\n'
        '  [cyan]q[/cyan]                 退出',
        title='[bold]轻小说文库 CLI 工具[/bold]',
        expand=False,
    ))
    while True:
        try:
            raw = input('\nwenk8> ').strip()
            if not raw:
                continue
            low = raw.lower()
            if low in ('q', 'quit', 'exit'):
                break
            parts = raw.split()
            cmd = parts[0].lower()

            if cmd == 'info' and len(parts) >= 2:
                show_book_info(extract_book_id(parts[1]) or parts[1], base_url=args.base_url, cookie=args.cookie)
            elif cmd == 'author' and len(parts) >= 2:
                ed = Editer(root_path=args.out_dir, base_url=args.base_url, cookie=args.cookie)
                print_book_cards(ed.search_books(' '.join(parts[1:]), scope='author'), title='作者作品')
            elif cmd == 'search' and len(parts) >= 2:
                ed = Editer(root_path=args.out_dir, base_url=args.base_url, cookie=args.cookie)
                print_book_cards(ed.search_books(' '.join(parts[1:]), scope='title'), title='书名搜索')
            elif cmd == 'toplist':
                sort_key = parts[1] if len(parts) >= 2 else 'allvisit'
                ed = Editer(root_path=args.out_dir, base_url=args.base_url, cookie=args.cookie)
                print_book_cards(ed.fetch_toplist(sort=sort_key), title=f'榜单 ({sort_key})')
            elif cmd == 'reviews' and len(parts) >= 2:
                show_reviews(extract_book_id(parts[1]) or parts[1], base_url=args.base_url, cookie=args.cookie)
            elif cmd == 'thread' and len(parts) >= 2:
                show_review_thread(parts[1], base_url=args.base_url, cookie=args.cookie)
            elif cmd == 'read' and len(parts) >= 3:
                read_chapter_cli(extract_book_id(parts[1]) or parts[1], parts[2], base_url=args.base_url, cookie=args.cookie)
            else:
                vol_input = input('请输入卷号（留空回车查目录，支持 2 / 1-3 / 1,2,3 / all）：').strip()
                downloader_router(
                    root_path=args.out_dir,
                    book_no=raw,
                    volume_no=vol_input,
                    base_url=args.base_url,
                    max_thread_num=args.threads,
                    args=args,
                )
        except KeyboardInterrupt:
            print('\n已中断。')
            break
        except Exception as exc:
            console.print(f'[red]执行出错：{exc}[/red]')


if __name__ == '__main__':
    cli_args = parse_args()
    if (
        cli_args.no_input
        or cli_args.search
        or cli_args.toplist
        or cli_args.reviews
        or cli_args.review_id
        or cli_args.read
        or cli_args.info
    ):
        try:
            run_cli_from_args(cli_args)
        except Exception as exc:
            console.print(f'[red]运行出错：{exc}[/red]')
            raise SystemExit(1)
    else:
        interactive_loop(cli_args)
