import argparse
import os
from typing import List, Optional

from Editer import DownloadCancelled, Editer
from utils import extract_book_id


def parse_args():
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(description='轻小说文库 (wenku8) EPUB 下载器')
    parser.add_argument('--book_no', default='', type=str, help='书籍编号或书籍网址')
    parser.add_argument(
        '--volume_no',
        default='',
        type=str,
        help='卷号（空字符串查询目录；支持 2、1-3、1,2,3、all）',
    )
    parser.add_argument('--out_dir', default='./out', type=str, help='EPUB 输出目录')
    parser.add_argument('--base_url', default='https://www.wenku8.cc', type=str, help='站点域名或镜像地址')
    parser.add_argument('--threads', default=8, type=int, help='图片下载并发线程数')
    parser.add_argument('--no_input', action='store_true', help='非交互模式，直接按参数执行')
    return parser.parse_args()


def parse_volume_spec(volume_no: str) -> Optional[List[int]]:
    """Parse volume specification string into ordered unique 1-based volume indices.

    Returns None when volume_no is empty (meaning query catalog only).
    Raises ValueError on invalid format.
    """
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


def query_chaps(
    book_no: str,
    root_path: str = './out',
    base_url: str = 'https://www.wenku8.cc',
    cancel_event=None,
):
    print('未输入卷号，将返回书籍目录信息......')
    editer = Editer(
        root_path=root_path,
        book_no=book_no,
        base_url=base_url,
        cancel_event=cancel_event,
    )
    editer.fetch_book_info()
    print('*******************************')
    print(f'书名：{editer.title}')
    print(f'作者：{editer.author}')
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
):
    editer = Editer(
        root_path=root_path,
        book_no=book_no,
        volume_no=volume_no,
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
):
    book_id = extract_book_id(str(book_no))
    if not book_id:
        print('请检查书号或书籍网址是否完整正确！')
        return []

    raw_vol = str(volume_no).strip() if volume_no is not None else ''
    if raw_vol == '':
        query_chaps(book_id, root_path=root_path, base_url=base_url, cancel_event=cancel_event)
        return []

    if raw_vol.lower() in ('all', '*'):
        volume_titles = query_chaps(
            book_id,
            root_path=root_path,
            base_url=base_url,
            cancel_event=cancel_event,
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
            base_url=base_url,
            max_thread_num=max_thread_num,
            cancel_event=cancel_event,
        )
        if epub_file:
            output_files.append(epub_file)

    if len(volume_no_list) > 1 and output_files:
        print(f'所有下载任务完成！共生成 {len(output_files)} 本 EPUB。')
    return output_files


if __name__ == '__main__':
    args = parse_args()

    if args.no_input:
        try:
            downloader_router(
                root_path=args.out_dir,
                book_no=args.book_no,
                volume_no=args.volume_no,
                base_url=args.base_url,
                max_thread_num=args.threads,
            )
        except Exception as exc:
            print(f'运行出错：{exc}')
    else:
        while True:
            try:
                book_input = input('请输入书籍号（或完整书籍网址，输入 q 退出）：').strip()
                if book_input.lower() in ('q', 'quit', 'exit'):
                    break
                vol_input = input('请输入卷号（留空回车查目录，支持 2 / 1-3 / 1,2,3 / all）：').strip()
                downloader_router(
                    root_path=args.out_dir,
                    book_no=book_input,
                    volume_no=vol_input,
                    base_url=args.base_url,
                    max_thread_num=args.threads,
                )
            except KeyboardInterrupt:
                print('\n已中断。')
                break
            except Exception as exc:
                print(f'执行出错：{exc}')
