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
    @Query private var visits: [Visit]

    @State private var position: MapCameraPosition = .region(.tokyo)
    @State private var selectedID: String?
    @State private var filter: VisitFilter = .all
    @State private var searchText = ""
    @State private var location = LocationPermission()

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
        let conquered = store.shops.filter { visitedIDs.contains($0.id) }.count

        NavigationStack {
            Map(position: $position, selection: $selectedID) {
                UserAnnotation()
                ForEach(shops) { shop in
                    let visited = visitedIDs.contains(shop.id)
                    Marker(shop.name,
                           systemImage: visited ? "checkmark" : "fork.knife",
                           coordinate: shop.coordinate)
                        .tint(visited ? Color.green : Color.orange)
                        .tag(shop.id)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
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
            .overlay(alignment: .bottom) {
                if let error = store.lastError {
                    Text(error)
                        .font(.caption)
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                } else if store.isLoading && store.shops.isEmpty {
                    ProgressView("店舗データを読み込み中…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("すするマップ")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "店名・地域で検索")
            .onSubmit(of: .search) {
                guard let first = shops.first else { return }
                withAnimation {
                    position = .region(MKCoordinateRegion(
                        center: first.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                }
                selectedID = first.id
            }
            .sheet(item: selectedShop) { shop in
                NavigationStack {
                    ShopDetailView(shop: shop)
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear { location.requestIfNeeded() }
        }
    }

    private var selectedShop: Binding<Shop?> {
        Binding(
            get: { selectedID.flatMap { store.shop(id: $0) } },
            set: { selectedID = $0?.id }
        )
    }
}
