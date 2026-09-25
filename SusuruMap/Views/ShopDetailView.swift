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
    @AppStorage(MapApp.storageKey) private var mapApp: MapApp = .inApp
    @AppStorage("addVisitsToCalendar") private var addToCalendar = false

    @State private var reviews: [Review] = []
    @State private var myUserID: String?
    @State private var isLoadingReviews = false
    @State private var reviewError: String?

    /// ワンタップで記録した直後の訪問（「編集」「取り消す」を出すため）
    @State private var justAdded: Visit?
    @State private var editingVisit: Visit?
    @State private var calendarError: String?
    @State private var confirmingUndo = false
    @State private var showingComposer = false
    @State private var reportTarget: Review?
    @State private var deleteTarget: Review?

    init(shop: Shop) {
        self.shop = shop
        let shopID = shop.id
        _visits = Query(filter: #Predicate<Visit> { $0.shopId == shopID },
                        sort: \Visit.visitedAt, order: .reverse)
    }

    private var todaysVisit: Visit? {
        visits.first { Calendar.current.isDateInToday($0.visitedAt) }
    }
    private var visitedToday: Bool { todaysVisit != nil }

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
        .sensoryFeedback(.success, trigger: visits.count) { old, new in new > old }
        .sheet(item: $editingVisit, onDismiss: { justAdded = nil }) { visit in
            VisitEditor(visit: visit)
        }
        .sheet(isPresented: $showingComposer) {
            ReviewComposer(shop: shop, visitedAt: visits.first?.visitedAt ?? Date()) {
                // レビューを書いた店は「行った」ことにする（まだ記録がなければ今日の日付で）
                if visits.isEmpty { recordVisit() }
                Task { await loadReviews() }
            }
        }
        .confirmationDialog("自分のレビューを削除しますか？", isPresented: Binding(
            get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }
        ), titleVisibility: .visible, presenting: deleteTarget) { review in
            Button("削除する", role: .destructive) { Task { await delete(review) } }
        } message: { _ in
            Text("写真も一緒に消え、元に戻せません。")
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
            // 押すたびに「記録」⇄「取り消し」が切り替わる
            Button {
                toggleTodaysVisit()
            } label: {
                VStack(spacing: 2) {
                    Label(visitedToday ? "行った！" : "行った！を記録",
                          systemImage: visitedToday ? "checkmark.seal.fill" : "circle")
                        .font(.headline)
                    if visitedToday {
                        Text("もう一度押すと取り消し").font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(visitedToday ? .green : .orange)
            .confirmationDialog("今日の「行った！」を取り消しますか？", isPresented: $confirmingUndo, titleVisibility: .visible) {
                Button("取り消す（メモも消えます）", role: .destructive) { undoTodaysVisit() }
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
            if let url = mapApp.externalApp.placeURL(name: shop.name, latitude: shop.latitude, longitude: shop.longitude) {
                Button { openURL(url) } label: {
                    Label("\(mapApp.externalApp.rawValue)で開く", systemImage: "map")
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
        Section {
            if let added = justAdded {
                HStack {
                    Label("記録しました", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("日付・メモを変える") { editingVisit = added }
                        .buttonStyle(.borderless)
                }
                .font(.subheadline)
            }
            if let calendarError {
                Text("カレンダーに登録できませんでした：\(calendarError)")
                    .font(.caption).foregroundStyle(.red)
            }
            if visits.isEmpty {
                Text("まだ行っていません").foregroundStyle(.secondary)
            }
            ForEach(visits) { visit in
                Button { editingVisit = visit } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(visit.visitedAt.formatted(date: .long, time: .omitted))
                                .foregroundStyle(.primary)
                            if !visit.memo.isEmpty {
                                Text(visit.memo).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(visits[i]) }
                justAdded = nil
            }
        } header: {
            Text("自分の訪問記録")
        } footer: {
            if !visits.isEmpty {
                Text("タップすると日付やメモを変更できます。")
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
                ReviewRow(
                    review: review,
                    isMine: review.userId == myUserID,
                    onDelete: { deleteTarget = review },
                    onReport: { reportTarget = review },
                    onHideUser: { hideUser(of: review) }
                )
                .contextMenu { reviewMenu(review) }
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
            Button("削除", systemImage: "trash", role: .destructive) { deleteTarget = review }
        } else {
            Button("通報する", systemImage: "exclamationmark.bubble") { reportTarget = review }
            Button("このユーザーを非表示", systemImage: "eye.slash") { hideUser(of: review) }
        }
    }

    // MARK: - Actions

    private func hideUser(of review: Review) {
        var ids = BlockList.decode(blockedRaw)
        ids.insert(review.userId)
        blockedRaw = BlockList.encode(ids)
    }

    /// 「行った！」ボタン：まだなら記録、記録済みなら取り消す
    private func toggleTodaysVisit() {
        guard let visit = todaysVisit else { recordVisit(); return }
        // メモを書いた記録は、うっかり消さないよう確認してから
        if visit.memo.isEmpty { undoTodaysVisit() } else { confirmingUndo = true }
    }

    private func undoTodaysVisit() {
        guard let visit = todaysVisit else { return }
        if justAdded == visit { justAdded = nil }
        context.delete(visit)
        try? context.save()
    }

    /// ワンタップで今日の訪問を記録する
    private func recordVisit() {
        let visit = Visit(shopId: shop.id, shopName: shop.name, visitedAt: Date())
        context.insert(visit)
        try? context.save()
        justAdded = visit
        calendarError = nil
        if addToCalendar {
            Task {
                do {
                    try await CalendarSync.addVisit(shop: shop, date: visit.visitedAt, memo: "")
                } catch {
                    calendarError = error.localizedDescription
                }
            }
        }
    }

    private func loadReviews() async {
        isLoadingReviews = true
        defer { isLoadingReviews = false }
        do {
            reviews = try await services.reviews.reviews(for: shop.allIDs)
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
