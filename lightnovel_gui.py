# coding:utf-8
import base64
import importlib.util
import os
import sys
import threading

from PyQt5.QtCore import QObject, QThread, QUrl, Qt, pyqtSignal
from PyQt5.QtGui import QColor, QDesktopServices, QFont, QIcon, QPixmap, QTextCursor
from PyQt5.QtWidgets import (
    QApplication,
    QFileDialog,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QVBoxLayout,
)
from qfluentwidgets import (
    ComboBoxSettingCard,
    EditableComboBox,
    ExpandLayout,
    FluentIcon as FIF,
    FluentWindow,
    ImageLabel,
    InfoBar,
    InfoBarPosition,
    LineEdit,
    NavigationItemPosition,
    OptionsConfigItem,
    OptionsSettingCard,
    OptionsValidator,
    PrimaryPushButton,
    ProgressRing,
    PushButton,
    PushSettingCard,
    SettingCard,
    SettingCardGroup,
    SubtitleLabel,
    TextEdit,
    Theme,
    qconfig,
    setTheme,
    setThemeColor,
)

from Editer import DownloadCancelled
from lightnovel import downloader_router
from utils import extract_book_id


def _load_resource_attr(module_file: str, attr_name: str) -> str:
    """Load Base64 resource constant safely without colliding with POSIX stdlib 'resource'."""
    file_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'resource', module_file)
    spec = importlib.util.spec_from_file_location(f'_local_resource_{module_file[:-3]}', file_path)
    if spec is None or spec.loader is None:
        return ''
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, attr_name, '')


book_base64 = _load_resource_attr('book.py', 'book_base64')
logo_base64 = _load_resource_attr('logo.py', 'logo_base64')


def make_ui_font(point_size: int) -> QFont:
    """Create a cross-platform UI font without hardcoding Windows-only fonts."""
    if sys.platform == 'darwin':
        family = 'PingFang SC'
    elif sys.platform.startswith('win'):
        family = 'Microsoft YaHei'
    else:
        family = 'Sans Serif'
    font = QFont(family, point_size)
    font.setStyleStrategy(QFont.PreferAntialias)
    return font


class EmittingStr(QObject):
    textWritten = pyqtSignal(str)

    def write(self, text):
        if text:
            self.textWritten.emit(str(text))

    def flush(self):
        pass

    def isatty(self):
        return False


class DownloadWorker(QThread):
    finished_signal = pyqtSignal(bool, str)

    def __init__(
        self,
        out_path: str,
        book_input: str,
        volume_input: str,
        base_url: str,
        max_thread_num: int,
        progress_signal,
        cover_signal,
        clear_signal,
    ):
        super().__init__()
        self.out_path = out_path
        self.book_input = book_input
        self.volume_input = volume_input
        self.base_url = base_url
        self.max_thread_num = max_thread_num
        self.progress_signal = progress_signal
        self.cover_signal = cover_signal
        self.clear_signal = clear_signal
        self.cancel_event = threading.Event()

    def request_cancel(self):
        self.cancel_event.set()

    def run(self):
        self.clear_signal.emit('')
        try:
            outputs = downloader_router(
                root_path=self.out_path,
                book_no=self.book_input,
                volume_no=self.volume_input,
                is_gui=True,
                progressring_signal=self.progress_signal,
                cover_signal=self.cover_signal,
                base_url=self.base_url,
                max_thread_num=self.max_thread_num,
                cancel_event=self.cancel_event,
            )
            if self.cancel_event.is_set():
                self.finished_signal.emit(False, '已取消')
            elif (self.volume_input or '').strip() == '':
                self.finished_signal.emit(True, '目录查询完成')
            elif outputs:
                self.finished_signal.emit(True, f'下载完成，共生成 {len(outputs)} 本 EPUB')
            else:
                self.finished_signal.emit(False, '未生成 EPUB，请查看上方日志')
        except DownloadCancelled:
            print('\n[提示] 下载任务已由用户取消。')
            self.finished_signal.emit(False, '下载已取消')
        except Exception as exc:
            print(f'\n[错误] {exc}')
            self.finished_signal.emit(False, str(exc))


class BaseUrlSettingCard(SettingCard):
    """Setting card allowing selection or custom input of wenku8 site/mirror URL."""

    urlChanged = pyqtSignal(str)

    def __init__(self, icon, title: str, content: str, default_url: str, parent=None):
        super().__init__(icon, title, content, parent)
        self.comboBox = EditableComboBox(self)
        self.comboBox.setMinimumWidth(240)
        self.comboBox.addItems([
            'https://www.wenku8.cc',
            'https://www.wenku8.net',
        ])
        self.comboBox.setCurrentText(default_url)
        self.hBoxLayout.addWidget(self.comboBox, 0, Qt.AlignRight)
        self.hBoxLayout.addSpacing(16)
        self.comboBox.currentTextChanged.connect(self.urlChanged.emit)


class SettingWidget(QFrame):
    def __init__(self, text: str, parent=None):
        super().__init__(parent=parent)
        self.parent_window = parent
        self.setObjectName(text.replace(' ', '-'))
        self.expandLayout = ExpandLayout(self)

        self.download_group = SettingCardGroup(self.tr('下载设置'), self)
        self.appearance_group = SettingCardGroup(self.tr('外观设置'), self)

        self.download_path_card = PushSettingCard(
            self.tr('选择文件夹'),
            FIF.DOWNLOAD,
            self.tr('下载目录'),
            self.parent_window.out_path,
            self.download_group,
        )

        self.base_url_card = BaseUrlSettingCard(
            FIF.GLOBE,
            self.tr('站点地址 / 镜像'),
            self.tr('默认 https://www.wenku8.cc，如受限自动回退主站或手动切换'),
            self.parent_window.base_url,
            self.download_group,
        )

        self.thread_config = OptionsConfigItem(
            'Download',
            'ThreadCount',
            str(self.parent_window.max_threads),
            OptionsValidator(['4', '8', '12', '16']),
        )
        self.thread_card = ComboBoxSettingCard(
            self.thread_config,
            FIF.SPEED_HIGH,
            self.tr('图片并发线程数'),
            self.tr('同时下载插图的线程数量'),
            texts=['4', '8', '12', '16'],
            parent=self.download_group,
        )

        self.theme_config = OptionsConfigItem(
            'Appearance',
            'ThemeMode',
            Theme.DARK,
            OptionsValidator(Theme),
        )
        self.theme_card = OptionsSettingCard(
            self.theme_config,
            FIF.BRUSH,
            self.tr('应用主题'),
            self.tr('更改外观'),
            texts=[self.tr('亮'), self.tr('暗'), self.tr('跟随系统设置')],
            parent=self.appearance_group,
        )

        self.download_group.addSettingCard(self.download_path_card)
        self.download_group.addSettingCard(self.base_url_card)
        self.download_group.addSettingCard(self.thread_card)
        self.appearance_group.addSettingCard(self.theme_card)

        self.expandLayout.setSpacing(24)
        self.expandLayout.setContentsMargins(20, 12, 20, 20)
        self.expandLayout.addWidget(self.download_group)
        self.expandLayout.addWidget(self.appearance_group)

        self.download_path_card.clicked.connect(self.download_path_changed)
        self.base_url_card.urlChanged.connect(self.base_url_changed)
        self.thread_config.valueChanged.connect(self.thread_count_changed)
        self.theme_card.optionChanged.connect(self.theme_changed)

    def download_path_changed(self):
        selected = QFileDialog.getExistingDirectory(
            self, self.tr('选择下载目录'), self.parent_window.out_path
        )
        if selected:
            self.parent_window.out_path = selected
            self.download_path_card.setContent(selected)

    def base_url_changed(self, url: str):
        cleaned = (url or '').strip()
        if cleaned:
            self.parent_window.base_url = cleaned

    def thread_count_changed(self, val: str):
        try:
            self.parent_window.max_threads = int(val)
        except (TypeError, ValueError):
            self.parent_window.max_threads = 8

    def theme_changed(self):
        theme_name = self.theme_card.choiceLabel.text()
        self.parent_window.set_theme(theme_name)


class HomeWidget(QFrame):
    progressring_signal = pyqtSignal(object)
    clear_signal = pyqtSignal(object)
    cover_signal = pyqtSignal(object)

    def __init__(self, text: str, parent=None):
        super().__init__(parent=parent)
        self.setObjectName(text.replace(' ', '-'))
        self.parent_window = parent
        self.worker = None

        font_label = make_ui_font(14)
        font_msg = make_ui_font(11)

        self.label_book = SubtitleLabel('书号 / 网址：', self)
        self.label_volumn = SubtitleLabel('卷号：', self)
        self.editline_book = LineEdit(self)
        self.editline_volumn = LineEdit(self)

        self.editline_book.setClearButtonEnabled(True)
        self.editline_volumn.setClearButtonEnabled(True)
        self.editline_book.setPlaceholderText('输入书号（如 3138）或粘贴 wenku8 书籍链接')
        self.editline_volumn.setPlaceholderText('留空查目录；支持 2、1-3、1,2,3 或 all')

        self.book_icon = QPixmap()
        self.book_icon.loadFromData(base64.b64decode(book_base64))
        self.cover_w, self.cover_h = 160, 236

        self.label_cover = ImageLabel(self.book_icon, self)
        self.label_cover.setBorderRadius(8, 8, 8, 8)
        self.label_cover.setFixedSize(self.cover_w, self.cover_h)

        self.text_screen = TextEdit(self)
        self.text_screen.setReadOnly(True)
        self.text_screen.setMinimumHeight(self.cover_h)

        self.progressRing = ProgressRing(self)
        self.progressRing.setValue(0)
        self.progressRing.setTextVisible(True)
        self.progressRing.setFixedSize(56, 56)
        self.progressRing.hide()

        self.btn_query = PushButton(FIF.SEARCH, '查询目录', self)
        self.btn_run = PrimaryPushButton(FIF.DOWNLOAD, '开始下载', self)
        self.btn_run.setShortcut(Qt.Key_Return)
        self.btn_stop = PushButton(FIF.CANCEL, '取消', self)
        self.btn_stop.setEnabled(False)
        self.btn_open_dir = PushButton(FIF.FOLDER, '打开目录', self)

        self.label_book.setFont(font_label)
        self.label_volumn.setFont(font_label)
        self.editline_book.setFont(font_label)
        self.editline_volumn.setFont(font_label)
        self.text_screen.setFont(font_msg)

        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(20, 14, 20, 16)
        main_layout.setSpacing(12)

        form_layout = QGridLayout()
        form_layout.setHorizontalSpacing(12)
        form_layout.setVerticalSpacing(10)
        form_layout.addWidget(self.label_book, 0, 0)
        form_layout.addWidget(self.editline_book, 0, 1)
        form_layout.addWidget(self.label_volumn, 1, 0)
        form_layout.addWidget(self.editline_volumn, 1, 1)

        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(10)
        btn_layout.addWidget(self.btn_query)
        btn_layout.addWidget(self.btn_run)
        btn_layout.addWidget(self.btn_stop)
        btn_layout.addWidget(self.btn_open_dir)
        form_layout.addLayout(btn_layout, 2, 1)

        content_layout = QHBoxLayout()
        content_layout.setSpacing(14)
        content_layout.addWidget(self.text_screen, stretch=1)

        right_panel = QVBoxLayout()
        right_panel.setSpacing(10)
        right_panel.addWidget(self.label_cover, alignment=Qt.AlignTop | Qt.AlignHCenter)
        right_panel.addWidget(self.progressRing, alignment=Qt.AlignCenter)
        right_panel.addStretch(1)
        content_layout.addLayout(right_panel)

        main_layout.addLayout(form_layout)
        main_layout.addLayout(content_layout, stretch=1)

        self.btn_query.clicked.connect(self.query_catalog)
        self.btn_run.clicked.connect(self.process_start)
        self.btn_stop.clicked.connect(self.process_stop)
        self.btn_open_dir.clicked.connect(self.open_output_dir)

        self.progressring_signal.connect(self.progressring_msg)
        self.clear_signal.connect(self.clear_screen)
        self.cover_signal.connect(self.display_cover)

        self._orig_stdout = sys.stdout
        self._orig_stderr = sys.stderr
        self._emitter = EmittingStr(textWritten=self.outputWritten)
        sys.stdout = self._emitter
        sys.stderr = self._emitter
        self.text_screen.setText(self.parent_window.welcome_text)

    def restore_streams(self):
        sys.stdout = self._orig_stdout
        sys.stderr = self._orig_stderr

    def _reset_cover(self):
        self.label_cover.setImage(self.book_icon)
        self.label_cover.setFixedSize(self.cover_w, self.cover_h)

    def _set_running_state(self, running: bool, mode: str = 'download'):
        self.btn_query.setEnabled(not running)
        self.btn_run.setEnabled(not running)
        self.btn_stop.setEnabled(running)
        if running:
            self.btn_run.setText('正在查询...' if mode == 'query' else '正在下载...')
        else:
            self.btn_run.setText('开始下载')
            self.btn_stop.setText('取消')

    def _launch_worker(self, book_input: str, volume_input: str, mode: str):
        if self.worker is not None and self.worker.isRunning():
            return

        if not extract_book_id(book_input):
            InfoBar.warning(
                title='输入有误',
                content='请输入有效的书号（数字）或 wenku8 书籍链接',
                parent=self,
                position=InfoBarPosition.TOP,
                duration=2500,
            )
            return

        self._reset_cover()
        self._set_running_state(True, mode=mode)
        self.worker = DownloadWorker(
            out_path=self.parent_window.out_path,
            book_input=book_input,
            volume_input=volume_input,
            base_url=self.parent_window.base_url,
            max_thread_num=self.parent_window.max_threads,
            progress_signal=self.progressring_signal,
            cover_signal=self.cover_signal,
            clear_signal=self.clear_signal,
        )
        self.worker.finished_signal.connect(self.on_worker_finished)
        self.worker.start()

    def query_catalog(self):
        self._launch_worker(self.editline_book.text(), '', mode='query')

    def process_start(self):
        vol_text = self.editline_volumn.text().strip()
        mode = 'query' if vol_text == '' else 'download'
        self._launch_worker(self.editline_book.text(), vol_text, mode=mode)

    def process_stop(self):
        if self.worker is not None and self.worker.isRunning():
            self.btn_stop.setEnabled(False)
            self.btn_stop.setText('取消中...')
            self.worker.request_cancel()

    def on_worker_finished(self, success: bool, message: str):
        self._set_running_state(False)
        self.progressRing.hide()
        self.progressRing.setValue(0)
        if success:
            InfoBar.success(
                title='完成',
                content=message,
                parent=self,
                position=InfoBarPosition.TOP,
                duration=3000,
            )
        else:
            InfoBar.warning(
                title='提示',
                content=message,
                parent=self,
                position=InfoBarPosition.TOP,
                duration=3500,
            )

    def open_output_dir(self):
        out_dir = self.parent_window.out_path
        os.makedirs(out_dir, exist_ok=True)
        QDesktopServices.openUrl(QUrl.fromLocalFile(out_dir))

    def outputWritten(self, text: str):
        cursor = self.text_screen.textCursor()
        scrollbar = self.text_screen.verticalScrollBar()
        is_bottom = scrollbar.value() >= scrollbar.maximum() - 15
        cursor.movePosition(QTextCursor.End)
        cursor.insertText(text)
        if is_bottom:
            self.text_screen.setTextCursor(cursor)

    def clear_screen(self, _=None):
        self.text_screen.clear()

    def display_cover(self, signal_msg):
        filepath, img_h, img_w = signal_msg
        if img_h and img_w:
            scaled_w = max(80, min(220, int(img_w * self.cover_h / img_h)))
            self.label_cover.setImage(filepath)
            self.label_cover.setFixedSize(scaled_w, self.cover_h)

    def progressring_msg(self, val):
        if val == 'start':
            self.progressRing.setValue(0)
            self.progressRing.show()
        elif val == 'end':
            self.progressRing.hide()
            self.progressRing.setValue(0)
        elif isinstance(val, int):
            self.progressRing.setValue(val)


class Window(FluentWindow):
    def __init__(self):
        super().__init__()
        self.out_path = os.path.join(os.path.expanduser('~'), 'Downloads')
        self.base_url = 'https://www.wenku8.cc'
        self.max_threads = 8

        split_str = '----------------------------------------\n'
        self.welcome_text = (
            '使用说明：\n'
            f'{split_str}'
            '1. 输入轻小说文库书号（如 3138，不限位数），或直接粘贴书籍页链接。\n'
            '2. 点击「查询目录」或将卷号留空点击「开始下载」，可查看全部分卷编号。\n'
            '3. 卷号支持单卷（2）、连续范围（1-3）、离散列表（1,2,3）或全部（all）。\n'
            '4. 若主站访问受限，可在左侧「设置」中切换镜像地址或调整下载线程与目录。\n'
        )

        self.homeInterface = HomeWidget('Home Interface', self)
        self.settingInterface = SettingWidget('Setting Interface', self)
        self.initNavigation()
        self.initWindow()

    def initNavigation(self):
        self.addSubInterface(self.homeInterface, FIF.HOME, '主界面')
        self.addSubInterface(
            self.settingInterface, FIF.SETTING, '设置', NavigationItemPosition.BOTTOM
        )

    def initWindow(self):
        self.resize(760, 500)
        self.setMinimumSize(640, 440)
        pixmap = QPixmap()
        pixmap.loadFromData(base64.b64decode(logo_base64))
        self.setWindowIcon(QIcon(pixmap))
        self.setWindowTitle('轻小说文库 EPUB 下载器')
        self.setFont(make_ui_font(12))

        desktop = QApplication.desktop().availableGeometry()
        self.move(desktop.width() // 2 - self.width() // 2, desktop.height() // 2 - self.height() // 2)

    def set_theme(self, mode=None):
        if mode == '亮':
            setTheme(Theme.LIGHT)
        elif mode == '暗':
            setTheme(Theme.DARK)
        elif mode == '跟随系统设置':
            setTheme(Theme.AUTO)

        color = QColor(255, 255, 255) if qconfig.theme == Theme.DARK else QColor(0, 0, 0)
        self.homeInterface.label_book.setTextColor(color)
        self.homeInterface.label_volumn.setTextColor(color)

    def closeEvent(self, event):
        worker = self.homeInterface.worker
        if worker is not None and worker.isRunning():
            worker.request_cancel()
            worker.wait(3000)
        self.homeInterface.restore_streams()
        super().closeEvent(event)


if __name__ == '__main__':
    QApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps)

    setTheme(Theme.DARK)
    setThemeColor('#559DCD')
    app = QApplication(sys.argv)
    w = Window()
    w.show()
    sys.exit(app.exec_())
