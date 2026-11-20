import SwiftUI
import Wenku8Core

struct ReviewsInspectorView: View {
    @EnvironmentObject var vm: StudioViewModel

    var body: some View {
        VStack(spacing: 0) {
            inspectorHeader
            Divider()

            if let selected = vm.selectedReview {
                threadDetailView(selected)
            } else {
                reviewListView
            }
        }
    }

    private var inspectorHeader: some View {
        HStack {
            if vm.selectedReview != nil {
                Button {
                    vm.selectedReview = nil
                    vm.reviewPosts = []
                } label: {
                    Label("返回列表", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Label("书评与吐槽", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
            }

            Spacer()

            Button {
                vm.showReviewsInspector = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭书评面板")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var reviewListView: some View {
        Group {
            if vm.isLoadingReviews {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在拉取书评列表...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.reviews.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("暂无书评")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.reviews) { rev in
                    Button {
                        vm.openReviewThread(rev)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(rev.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)

                            HStack {
                                Label(rev.author, systemImage: "person")
                                Spacer()
                                Label(rev.replyStats, systemImage: "bubble.left")
                                Text(rev.time.prefix(10))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
    }

    private func threadDetailView(_ review: BookReview) -> some View {
        Group {
            if vm.isLoadingReviewPosts {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载楼层回复...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(review.title)
                            .font(.headline)
                            .padding(.bottom, 4)

                        let orderedNodes = buildThreadedDisplay(posts: vm.reviewPosts)
                        ForEach(orderedNodes) { node in
                            FloorPostCard(
                                post: node.post,
                                isNestedReply: node.isNested,
                                quotedPost: node.quotedPost
                            )
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private struct DisplayNode: Identifiable {
        let post: ReviewPost
        let isNested: Bool
        let quotedPost: ReviewPost?
        var id: String { post.id }
    }

    private func buildThreadedDisplay(posts: [ReviewPost]) -> [DisplayNode] {
        guard !posts.isEmpty else { return [] }
        let byFloor = Dictionary(uniqueKeysWithValues: posts.map { ($0.floor, $0) })
        var nestedReplies: [Int: [ReviewPost]] = [:]
        var topLevel: [ReviewPost] = []

        for (idx, post) in posts.enumerated() {
            if idx == 0 {
                topLevel.append(post)
                continue
            }
            if let targetFloor = post.replyToFloor, byFloor[targetFloor] != nil, targetFloor < post.floor {
                nestedReplies[targetFloor, default: []].append(post)
            } else if let targetAuthor = post.replyToAuthor,
                      let matched = posts[..<idx].last(where: { $0.author == targetAuthor }) {
                nestedReplies[matched.floor, default: []].append(post)
            } else {
                topLevel.append(post)
            }
        }

        var output: [DisplayNode] = []
        var visitedFloors = Set<Int>()

        func appendWithChildren(_ post: ReviewPost, isNested: Bool, quoted: ReviewPost?) {
            guard !visitedFloors.contains(post.floor) else { return }
            visitedFloors.insert(post.floor)
            output.append(DisplayNode(post: post, isNested: isNested, quotedPost: quoted))
            for child in nestedReplies[post.floor] ?? [] {
                appendWithChildren(child, isNested: true, quoted: post)
            }
        }

        for root in topLevel {
            appendWithChildren(root, isNested: false, quoted: nil)
        }
        return output
    }
}

private struct FloorPostCard: View {
    let post: ReviewPost
    let isNestedReply: Bool
    let quotedPost: ReviewPost?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isNestedReply {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.45))
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    .padding(.trailing, 10)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("\(post.floor)#")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            post.floor == 1 ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14),
                            in: Capsule()
                        )
                        .foregroundStyle(post.floor == 1 ? Color.accentColor : Color.secondary)

                    Text(post.author)
                        .font(.caption.weight(.semibold))

                    Text(post.authorLevel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(post.time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let target = quotedPost {
                    HStack(spacing: 6) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.caption2)
                        Text("回复 \(target.floor)# \(target.author)：\(target.content)")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                } else if let replyFloor = post.replyToFloor {
                    Text("↳ 回复 \(replyFloor)#")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                } else if let replyAuthor = post.replyToAuthor {
                    Text("↳ 回复 @\(replyAuthor)")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }

                Text(post.content)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                post.floor == 1 ? Color.accentColor.opacity(0.07) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .padding(.leading, isNestedReply ? 12 : 0)
    }
}
