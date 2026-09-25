import Foundation
import MapKit

/// 地図に描くピンを減らすための仕組み。
///
/// 数千件のピンを一度に描くと地図が重くなるので、
///  1. 画面に見えている範囲の店だけを描く
///  2. それでも多いときは、近い店をまとめて「数字の丸（クラスタ）」1つにする
struct PinLayout {
    struct Cluster: Identifiable {
        let id: String
        let center: CLLocationCoordinate2D
        let count: Int
    }

    var singles: [Shop] = []
    var clusters: [Cluster] = []

    /// 1画面に個別のピンとして描く最大数
    static let maxSingles = 80
    /// まとめるときのマス目（横 × 縦）
    static let columns = 6
    static let rows = 10

    static func make(shops: [Shop], region: MKCoordinateRegion?) -> PinLayout {
        guard let region else {
            return PinLayout(singles: Array(shops.prefix(maxSingles)))
        }
        // 見えている範囲（少し広め）の店だけにする
        let latHalf = region.span.latitudeDelta * 0.6
        let lonHalf = region.span.longitudeDelta * 0.6
        let minLat = region.center.latitude - latHalf, maxLat = region.center.latitude + latHalf
        let minLon = region.center.longitude - lonHalf, maxLon = region.center.longitude + lonHalf
        let visible = shops.filter {
            $0.latitude >= minLat && $0.latitude <= maxLat && $0.longitude >= minLon && $0.longitude <= maxLon
        }
        if visible.count <= maxSingles {
            return PinLayout(singles: visible)
        }

        // 多すぎるのでマス目ごとにまとめる
        let cellLat = (maxLat - minLat) / Double(rows)
        let cellLon = (maxLon - minLon) / Double(columns)
        var buckets: [Int: [Shop]] = [:]
        for shop in visible {
            let r = min(rows - 1, Int((shop.latitude - minLat) / cellLat))
            let c = min(columns - 1, Int((shop.longitude - minLon) / cellLon))
            buckets[r * columns + c, default: []].append(shop)
        }
        var layout = PinLayout()
        for (key, group) in buckets {
            if group.count == 1 {
                layout.singles.append(group[0])
            } else {
                let lat = group.map(\.latitude).reduce(0, +) / Double(group.count)
                let lon = group.map(\.longitude).reduce(0, +) / Double(group.count)
                layout.clusters.append(Cluster(id: "c\(key)-\(group.count)",
                                               center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                               count: group.count))
            }
        }
        return layout
    }
}
