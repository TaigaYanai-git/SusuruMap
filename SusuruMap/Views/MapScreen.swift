import SwiftUI
import SwiftData
import MapKit
import UIKit

enum VisitFilter: String, CaseIterable, Identifiable {
    case all = "すべて"
    case notVisited = "未訪問"
    case visited = "行った"
    var id: Self { self }
}

struct MapScreen: View {
    @Environment(ShopStore.self) private var store
    @Environment(RoutePlanner.self) private var planner
    @Environment(LocationProvider.self) private var location
    @Environment(\.modelContext) private var context
    @Query private var visits: [Visit]

    /// 起動時は現在地を中心に（許可がなければ東京駅周辺）
    @State private var position: MapCameraPosition = .userLocation(fallback: .region(.tokyo))
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedID: String?
    @State private var filter: VisitFilter = .all
    @State private var searchText = ""
    @State private var showingNearby = false
    @State private var followingHeading = false

    var body: some View {
        let visitedIDs = Set(visits.map(\.shopId))
        let shops = store.shops.filter { shop in
            guard shop.matches(searchText) else { return false }
            switch filter {
            case .all: return true
            case .visited: return visitedIDs.contains(shop.id)
            case .notVisited: return !visitedIDs.contains(shop.id)
            }
        }
        let layout = PinLayout.make(shops: shops, region: visibleRegion)
        let shownIDs = Set(layout.singles.map(\.id))
        let conquered = store.shops.filter { visitedIDs.contains($0.id) }.count

        NavigationStack {
            Map(position: $position, selection: $selectedID) {
                // 自分の位置は青（お店のオレンジ・緑と見分けやすく）
                UserAnnotation()
                    .tint(Color.blue)

                if let route = planner.route {
                    MapPolyline(route.polyline)
                        .stroke(Color.blue, lineWidth: 6)
                }

                ForEach(layout.singles) { shop in
                    let visited = visitedIDs.contains(shop.id)
                    let isDestination = planner.destination?.id == shop.id
                    if isDestination {
                        Marker(shop.name, systemImage: "flag.fill", coordinate: shop.coordinate)
                            .tint(Color.blue)
                            .tag(shop.id)
                    } else {
                        // ラーメンどんぶりの記号（Assets の RamenPin）。行った店は緑、まだの店はオレンジ
                        Marker(shop.name, image: "RamenPin", coordinate: shop.coordinate)
                            .tint(visited ? Color.green : Color.orange)
                            .tag(shop.id)
                    }
                }

                ForEach(layout.clusters) { cluster in
                    Annotation("", coordinate: cluster.center, anchor: .center) {
                        Button { zoom(into: cluster.center) } label: {
                            ClusterBadge(count: cluster.count)
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }

                // 目的地がまとめられて見えなくなっても、旗は必ず表示する
                if let dest = planner.destination, !shownIDs.contains(dest.id) {
                    Marker(dest.name, systemImage: "flag.fill", coordinate: dest.coordinate)
                        .tint(Color.blue)
                        .tag(dest.id)
                }
            }
            // 地図の基本色を青に（自分の位置の点と、現在地ボタンなどの色）。お店のピンは個別に色を指定済み
            .tint(Color.blue)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                if followingHeading && !position.followsUserHeading { followingHeading = false }
            }
            .safeAreaInset(edge: .top) {
                if planner.isNavigating {
                    NavigationBanner()
                } else {
                VStack(spacing: 6) {
                    Picker("表示", selection: $filter) {
                        ForEach(VisitFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("\(conquered) / \(store.shops.count) 店を制覇")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if planner.isNavigating {
                    NavigationBottomBar()
                        .padding(.bottom, 8)
                } else if planner.destination != nil {
                    RouteCard()
                        .padding(.bottom, 8)
                } else if let error = store.lastError {
                    Text(error)
                        .font(.caption)
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
            .overlay {
                if store.isLoading && store.shops.isEmpty {
                    ProgressView("店舗データを読み込み中…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("すするマップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingNearby = true } label: {
                        Label("近くの店", systemImage: "location.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // 押すと、地図が自分の向いている方向に合わせて回る（もう一度押すと北が上に戻る）
                    Button {
                        followingHeading.toggle()
                        withAnimation {
                            position = followingHeading
                                ? .userLocation(followsHeading: true, fallback: .region(.tokyo))
                                : .userLocation(fallback: .region(.tokyo))
                        }
                    } label: {
                        Label(followingHeading ? "北を上にする" : "向いている方向に合わせる",
                              systemImage: followingHeading ? "location.north.line.fill" : "location.north.line")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "店名・地域で検索")
            .onSubmit(of: .search) {
                guard let first = shops.first else { return }
                focus(on: first)
            }
            .sheet(item: selectedShop) { shop in
                NavigationStack {
                    ShopDetailView(shop: shop)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingNearby) {
                NearbyShopsView(shops: store.shops, visitedIDs: visitedIDs) { shop in
                    showingNearby = false
                    focus(on: shop)
                }
                .presentationDetents([.medium, .large])
            }
            .onChange(of: planner.fitRequest) { _, _ in fitToRoute() }
            .onChange(of: location.location) { _, here in
                if let here { planner.update(with: here) }
            }
            .onChange(of: planner.isNavigating) { _, navigating in
                location.setNavigating(navigating)
                // ナビ中は画面が自動で消えないようにする
                UIApplication.shared.isIdleTimerDisabled = navigating
                withAnimation {
                    followingHeading = navigating
                    position = navigating
                        ? .userLocation(followsHeading: true, fallback: .region(.tokyo))
                        : .userLocation(fallback: .region(.tokyo))
                }
            }
            .alert("到着しました！", isPresented: Binding(
                get: { planner.arrivedAt != nil }, set: { if !$0 { planner.clearArrival() } }
            ), presenting: planner.arrivedAt) { shop in
                Button("行った！を記録") { recordArrival(at: shop) }
                Button("閉じる", role: .cancel) {}
            } message: { shop in
                Text("\(shop.name) に着きました。")
            }
            .onAppear { location.start() }
        }
    }

    private var selectedShop: Binding<Shop?> {
        Binding(
            get: { selectedID.flatMap { store.shop(id: $0) } },
            set: { selectedID = $0?.id }
        )
    }

    /// 到着したら、今日まだ記録していなければ「行った！」を記録する
    private func recordArrival(at shop: Shop) {
        let already = visits.contains { $0.shopId == shop.id && Calendar.current.isDateInToday($0.visitedAt) }
        if !already {
            context.insert(Visit(shopId: shop.id, shopName: shop.name, visitedAt: Date()))
            try? context.save()
        }
        planner.clear()
    }

    private func focus(on shop: Shop) {
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: shop.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        }
        selectedID = shop.id
    }

    /// まとめた丸をタップ → その場所を3倍に拡大
    private func zoom(into center: CLLocationCoordinate2D) {
        let span = visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: span.latitudeDelta / 3, longitudeDelta: span.longitudeDelta / 3)))
        }
    }

    /// 経路全体（経路がなければ目的地）が見えるように地図を動かす
    private func fitToRoute() {
        withAnimation {
            if let route = planner.route {
                let rect = route.polyline.boundingMapRect
                position = .rect(rect.insetBy(dx: -rect.size.width * 0.25, dy: -rect.size.height * 0.4))
            } else if let dest = planner.destination {
                position = .region(MKCoordinateRegion(
                    center: dest.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
            }
        }
    }
}

/// まとめたピン（数字の丸）
struct ClusterBadge: View {
    let count: Int

    var body: some View {
        let size: CGFloat = count >= 100 ? 46 : (count >= 10 ? 38 : 32)
        Text("\(count)")
            .font(.system(size: count >= 100 ? 13 : 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.orange))
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
            .accessibilityLabel("\(count)店。タップで拡大")
    }
}

/// 目的地を設定したとき画面下に出るカード
struct RouteCard: View {
    @Environment(RoutePlanner.self) private var planner
    @Environment(\.openURL) private var openURL
    @AppStorage(MapApp.storageKey) private var mapApp: MapApp = .inApp

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "flag.fill").foregroundStyle(.blue)
                Text(planner.destination?.name ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    planner.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("目的地を解除")
            }

            Picker("移動手段", selection: Binding(get: { planner.mode }, set: { planner.setMode($0) })) {
                ForEach(RoutePlanner.Mode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Group {
                if planner.isCalculating {
                    HStack(spacing: 8) { ProgressView(); Text("経路を計算中…") }
                } else if let route = planner.route {
                    Text("\(route.expectedTravelTime.travelTimeText)・\(route.distance.distanceText)")
                        .font(.title3.bold())
                        .monospacedDigit()
                } else if let error = planner.errorMessage {
                    Text(error).foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)

            HStack {
                Text("ナビに使うアプリ").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("ナビに使うアプリ", selection: $mapApp) {
                    ForEach(MapApp.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Button {
                    if mapApp == .inApp {
                        planner.startNavigation()
                    } else if let url = planner.navigationURL(app: mapApp) {
                        openURL(url)
                    }
                } label: {
                    Label("ナビ開始", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(mapApp == .inApp && planner.route == nil)

                Button {
                    // 電車の乗り換えはアプリ内では案内できないので、外部の地図アプリで開く
                    if let url = planner.navigationURL(app: mapApp.externalApp, transit: true) { openURL(url) }
                } label: {
                    Label("電車で", systemImage: "tram.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

/// ナビ中、画面上に出る「次の曲がり角」の案内
struct NavigationBanner: View {
    @Environment(RoutePlanner.self) private var planner

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol(for: planner.currentInstruction ?? ""))
                .font(.system(size: 34, weight: .bold))
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                if let meters = planner.distanceToNextTurn {
                    Text(meters.distanceText)
                        .font(.title2.bold())
                        .monospacedDigit()
                }
                Text(planner.currentInstruction ?? "経路に沿って進んでください")
                    .font(.headline)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding()
        .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    /// 案内の文から矢印の向きを決める
    private func symbol(for text: String) -> String {
        if text.contains("Uターン") { return "arrow.uturn.down" }
        if text.contains("右") { return "arrow.turn.up.right" }
        if text.contains("左") { return "arrow.turn.up.left" }
        if text.contains("目的地") || text.contains("到着") { return "flag.checkered" }
        return "arrow.up"
    }
}

/// ナビ中、画面下に出る残り時間・距離と終了ボタン
struct NavigationBottomBar: View {
    @Environment(RoutePlanner.self) private var planner

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let t = planner.remainingTime {
                    Text(t.travelTimeText).font(.title3.bold()).monospacedDigit()
                }
                HStack(spacing: 6) {
                    if let d = planner.remainingDistance { Text(d.distanceText) }
                    if let t = planner.remainingTime {
                        Text("・\(Date().addingTimeInterval(t).formatted(date: .omitted, time: .shortened)) 着")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                Text(planner.destination?.name ?? "")
                    .font(.caption)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                planner.toggleVoice()
            } label: {
                Image(systemName: planner.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title3)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(planner.voiceEnabled ? "音声案内をオフ" : "音声案内をオン")
            Button("終了") { planner.stopNavigation() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
