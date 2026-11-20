import SwiftUI
import Wenku8Core

struct TasksAndLogsView: View {
    @EnvironmentObject var vm: StudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            progressHeaderCard

            HSplitView {
                outputsSection
                    .frame(minWidth: 320)
                logsSection
                    .frame(minWidth: 300)
            }
        }
        .padding(18)
    }

    private var progressHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.currentStageText)
                        .font(.headline)
                    Text("输出目录：\(vm.outputDirectoryPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if vm.isDownloading {
                    Button("取消任务") {
                        vm.cancelDownload()
                    }
                    .buttonStyle(.glass)
                } else {
                    Button("打开下载目录") {
                        vm.openOutputFolder()
                    }
                    .buttonStyle(.glass)
                }
            }
            ProgressView(value: vm.progressFraction)
                .progressViewStyle(.linear)
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }

    private var outputsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已生成 EPUB（\(vm.outputs.count)）")
                    .font(.headline)
                Spacer()
                if !vm.outputs.isEmpty {
                    Button("清空记录") {
                        vm.outputs.removeAll()
                        vm.savePersistedState()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            if vm.outputs.isEmpty {
                Text("暂无生成产物")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.outputs) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text("\(URL(fileURLWithPath: item.filePath).lastPathComponent) · \(ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                Button("在 Finder 中显示") {
                                    vm.revealInFinder(item.filePath)
                                }
                                .buttonStyle(.glass)
                                Button("用默认阅读器打开") {
                                    vm.openFileWithDefaultReader(item.filePath)
                                }
                                .buttonStyle(.glassProminent)
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("运行日志")
                    .font(.headline)
                Spacer()
                Button("清空") { vm.logs.removeAll() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(vm.logs.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: vm.logs.count) { _, newCount in
                    if newCount > 0 {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
}
