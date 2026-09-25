import SwiftUI
import PhotosUI

/// レビュー投稿（評価・コメント・写真）
struct ReviewComposer: View {
    let shop: Shop
    var visitedAt: Date?
    var onPosted: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @AppStorage("displayName") private var displayName = ""

    @State private var rating = 4
    @State private var comment = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isPosting = false
    @State private var errorMessage: String?

    private var canPost: Bool {
        !displayName.trimmed.isEmpty
            && displayName.trimmed.count <= ReviewDraft.maxNameLength
            && comment.count <= ReviewDraft.maxCommentLength
            && !isPosting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("美味しさ") {
                    StarRatingPicker(rating: $rating)
                        .frame(maxWidth: .infinity)
                }
                Section {
                    TextField("スープ・麺・トッピングの感想など", text: $comment, axis: .vertical)
                        .lineLimit(4...10)
                } header: {
                    Text("コメント")
                } footer: {
                    Text("\(comment.count) / \(ReviewDraft.maxCommentLength)")
                        .foregroundStyle(comment.count > ReviewDraft.maxCommentLength ? Color.red : Color.secondary)
                }
                Section("ラーメンの写真") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoData == nil ? "写真を選ぶ" : "写真を変更", systemImage: "photo")
                    }
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button("写真を外す", role: .destructive) {
                            photoItem = nil
                            self.photoData = nil
                        }
                    }
                }
                Section {
                    TextField("ニックネーム", text: $displayName)
                } header: {
                    Text("投稿者名")
                } footer: {
                    Text(services.isSharedBackend
                         ? "レビューと写真はアプリの全ユーザーに公開されます。写真の位置情報は削除されます。"
                         : "Firebase未設定のため、この端末にだけ保存されます。")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(shop.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button("投稿") { Task { await post() } }.disabled(!canPost)
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let item else { return }
                    let raw = try? await item.loadTransferable(type: Data.self)
                    photoData = raw.flatMap { ImageCompressor.jpegData(from: $0) }
                }
            }
            .interactiveDismissDisabled(isPosting)
        }
    }

    private func post() async {
        isPosting = true
        defer { isPosting = false }
        let draft = ReviewDraft(
            shopId: shop.id,
            displayName: displayName.trimmed,
            rating: rating,
            comment: comment.trimmed,
            imageData: photoData,
            visitedAt: visitedAt
        )
        do {
            try await services.reviews.post(draft)
            onPosted()
            dismiss()
        } catch {
            errorMessage = "投稿に失敗しました：\(error.localizedDescription)"
        }
    }
}

struct ReviewRow: View {
    let review: Review

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(review.displayName).font(.subheadline.bold())
                Spacer()
                StarRatingView(rating: Double(review.rating)).font(.caption)
            }
            if let visitedAt = review.visitedAt {
                Text("訪問日: \(visitedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !review.comment.isEmpty {
                Text(review.comment)
            }
            if let url = review.photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    default:
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text(review.createdAt.formatted(.relative(presentation: .named)))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct StarRatingView: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: symbol(for: i))
            }
        }
        .foregroundStyle(.yellow)
        .accessibilityLabel(String(format: "5点中%.1f点", rating))
    }

    private func symbol(for i: Int) -> String {
        let v = rating - Double(i - 1)
        if v >= 0.75 { return "star.fill" }
        if v >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct StarRatingPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    rating = i
                } label: {
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.title)
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i)点")
            }
        }
    }
}
