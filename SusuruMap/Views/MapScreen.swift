import SwiftUI
import SwiftData
import MapKit

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
    @Query private var visits: [Visit]

    /// 起動時は現在地を中心に（許可がなければ東京駅周辺）
    @State private var position: MapCameraPosition = .userLocation(fallback: .region(.tokyo))
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedID: String?
    @State private var filter: VisitFilter = .all
    @State private var searchText = ""
    @State private var showingNearby = false

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
                UserAnnotation()

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
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
            }
            .safeAreaInset(edge: .top) {
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
            .safeAreaInset(edge: .bottom) {
                if planner.destination != nil {
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
            .onAppear { location.start() }
        }
    }

    private var selectedShop: Binding<Shop?> {
        Binding(
            get: { selectedID.flatMap { store.shop(id: $0) } },
            set: { selectedID = $0?.id }
        )
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
    @AppStorage(MapApp.storageKey) private var mapApp: MapApp = .apple

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
                    if let url = planner.navigationURL(app: mapApp) { openURL(url) }
                } label: {
                    Label("ナビ開始", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    if let url = planner.navigationURL(app: mapApp, transit: true) { openURL(url) }
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
