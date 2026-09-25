import SwiftUI
import SwiftData

/// 店舗の詳細（動画・訪問記録・みんなのレビュー）
struct ShopDetailView: View {
    let shop: Shop

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(AppServices.self) private var services
    @Environment(LocationProvider.self) private var location
    @Environment(RoutePlanner.self) private var planner
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query private var visits: [Visit]

    @AppStorage(BlockList.storageKey) private var blockedRaw = ""
    @AppStorage(MapApp.storageKey) private var mapApp: MapApp = .apple

    @State private var reviews: [Review] = []
    @State private var myUserID: String?
    @State private var isLoadingReviews = false
    @State private var reviewError: String?

    @State private var showingVisitEditor = false
    @State private var justVisitedOn: Date?
    @State private var askToReview = false
    @State private var showingComposer = false
    @State private var reportTarget: Review?

    init(shop: Shop) {
        self.shop = shop
        let shopID = shop.id
        _visits = Query(filter: #Predicate<Visit> { $0.shopId == shopID },
                        sort: \Visit.visitedAt, order: .reverse)
    }

    private var visibleReviews: [Review] {
        let blocked = BlockList.decode(blockedRaw)
        return reviews.filter { !blocked.contains($0.userId) }
    }

    var body: some View {
        List {
            headerSection
            videoSection
            visitSection
            reviewSection
        }
        .navigationTitle(shop.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadReviews() }
        .refreshable { await loadReviews() }
        .sheet(isPresented: $showingVisitEditor, onDismiss: {
            if justVisitedOn != nil { askToReview = true }
        }) {
            VisitEditor(shop: shop) { date in justVisitedOn = date }
        }
        .alert("レビューも書きますか？", isPresented: $askToReview) {
            Button("書く") { showingComposer = true }
            Button("あとで", role: .cancel) { justVisitedOn = nil }
        }
        .sheet(isPresented: $showingComposer, onDismiss: { justVisitedOn = nil }) {
            ReviewComposer(shop: shop, visitedAt: justVisitedOn ?? visits.first?.visitedAt) {
                Task { await loadReviews() }
            }
        }
        .confirmationDialog("このレビューを通報", isPresented: Binding(
            get: { reportTarget != nil }, set: { if !$0 { reportTarget = nil } }
        ), presenting: reportTarget) { review in
            ForEach(["不適切・攻撃的な内容", "スパム・宣伝", "無関係な写真", "その他"], id: \.self) { reason in
                Button(reason) { Task { try? await services.reviews.report(review, reason: reason) } }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(shop.name).font(.title3.bold())
                if let address = shop.address {
                    Text(address).font(.subheadline).foregroundStyle(.secondary)
                }
                if let meters = location.distance(to: shop) {
                    Label("現在地から \(meters.distanceText)", systemImage: "location")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if let avg = visibleReviews.averageRating {
                        StarRatingView(rating: avg)
                        Text(String(format: "%.1f（%ld件）", avg, visibleReviews.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !visits.isEmpty {
                        Label("行った！", systemImage: "checkmark.seal.fill")
                            .font(.caption.bold()).foregroundStyle(.green)
                    }
                }
            }
            Button {
                planner.setDestination(shop)
                router.tab = .map
                dismiss()
            } label: {
                Label(planner.destination?.id == shop.id ? "目的地に設定中" : "ここへ行く（目的地に設定）",
                      systemImage: "flag.fill")
            }
            .disabled(planner.destination?.id == shop.id)
            if let url = mapApp.placeURL(name: shop.name, latitude: shop.latitude, longitude: shop.longitude) {
                Button { openURL(url) } label: {
                    Label("\(mapApp.rawValue)で開く", systemImage: "map")
                }
            }
        }
    }

    private var videoSection: some View {
        Section("すするTVの動画") {
            ForEach(shop.videos) { video in
                Button { openURL(video.watchURL(shopName: shop.name)) } label: {
                    VideoRow(video: video)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var visitSection: some View {
        Section("自分の訪問記録") {
            if visits.isEmpty {
                Text("まだ行っていません").foregroundStyle(.secondary)
            }
            ForEach(visits) { visit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.visitedAt.formatted(date: .long, time: .omitted))
                    if !visit.memo.isEmpty {
                        Text(visit.memo).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(visits[i]) }
            }
            Button {
                showingVisitEditor = true
            } label: {
                Label(visits.isEmpty ? "行った！を記録" : "また行った！を記録", systemImage: "checkmark.circle")
            }
        }
    }

    private var reviewSection: some View {
        Section {
            if isLoadingReviews && reviews.isEmpty {
                ProgressView()
            } else if let reviewError {
                Text(reviewError).font(.caption).foregroundStyle(.red)
            } else if visibleReviews.isEmpty {
                Text("まだレビューがありません").foregroundStyle(.secondary)
            }
            ForEach(visibleReviews) { review in
                ReviewRow(review: review)
                    .contextMenu { reviewMenu(review) }
                    .swipeActions { if review.userId == myUserID {
                        Button("削除", role: .destructive) { Task { await delete(review) } }
                    } }
            }
            Button {
                showingComposer = true
            } label: {
                Label("レビューを書く", systemImage: "square.and.pencil")
            }
        } header: {
            Text("みんなのレビュー")
        } footer: {
            if !services.isSharedBackend {
                Text("レビューはこの端末にだけ保存されます。")
            }
        }
    }

    @ViewBuilder
    private func reviewMenu(_ review: Review) -> some View {
        if review.userId == myUserID {
            Button("削除", systemImage: "trash", role: .destructive) { Task { await delete(review) } }
        } else {
            Button("通報する", systemImage: "exclamationmark.bubble") { reportTarget = review }
            Button("このユーザーを非表示", systemImage: "eye.slash") {
                var ids = BlockList.decode(blockedRaw)
                ids.insert(review.userId)
                blockedRaw = BlockList.encode(ids)
            }
        }
    }

    // MARK: - Actions

    private func loadReviews() async {
        isLoadingReviews = true
        defer { isLoadingReviews = false }
        do {
            reviews = try await services.reviews.reviews(for: shop.id)
            myUserID = try? await services.reviews.currentUserID()
            reviewError = nil
        } catch {
            reviewError = "レビューを読み込めませんでした：\(error.localizedDescription)"
        }
    }

    private func delete(_ review: Review) async {
        do {
            try await services.reviews.delete(review)
            reviews.removeAll { $0.id == review.id }
        } catch {
            reviewError = "削除できませんでした：\(error.localizedDescription)"
        }
    }
}

struct VideoRow: View {
    let video: ShopVideo

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let thumb = video.thumbnailURL {
                    AsyncImage(url: thumb) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.2)
                    }
                } else {
                    Color.secondary.opacity(0.2)
                }
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .red)
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title).font(.subheadline).lineLimit(3)
                if let date = video.publishedDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                } else if video.videoId == nil {
                    Text("YouTubeで検索").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
