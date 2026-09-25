import SwiftUI
import UIKit
import CoreLocation

struct NearbyItem: Identifiable {
    let shop: Shop
    let distance: CLLocationDistance
    var id: String { shop.id }
}

/// 現在地から近い順の店一覧
struct NearbyShopsView: View {
    let shops: [Shop]
    let visitedIDs: Set<String>
    var onSelect: (Shop) -> Void

    @Environment(LocationProvider.self) private var location
    @Environment(\.openURL) private var openURL
    @State private var hideVisited = false

    var body: some View {
        NavigationStack {
            Group {
                if let here = location.location {
                    let nearest = nearestShops(from: here)
                    List {
                        Toggle("行った店を隠す", isOn: $hideVisited)
                        ForEach(nearest) { item in
                            Button { onSelect(item.shop) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.shop.name).foregroundStyle(.primary)
                                        if let pref = item.shop.prefecture {
                                            Text(pref).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if visitedIDs.contains(item.shop.id) {
                                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                                    }
                                    Text(item.distance.distanceText)
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if location.isAuthorized {
                    ProgressView("現在地を調べています…")
                } else {
                    ContentUnavailableView {
                        Label("現在地が分かりません", systemImage: "location.slash")
                    } description: {
                        Text("近くの店を探すには、設定アプリで「すするマップ」の位置情報を「使用中のみ」にしてください。")
                    } actions: {
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("近くの店")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { location.start() }
        }
    }

    private func nearestShops(from here: CLLocation) -> [NearbyItem] {
        let items = shops
            .filter { !hideVisited || !visitedIDs.contains($0.id) }
            .map { NearbyItem(shop: $0, distance: here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .sorted { $0.distance < $1.distance }
        return Array(items.prefix(50))
    }
}
