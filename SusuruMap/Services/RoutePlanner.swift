import Foundation
import MapKit
import Observation

/// 目的地と経路。地図に経路の線を引き、所要時間を出す。
@MainActor
@Observable
final class RoutePlanner {
    enum Mode: String, CaseIterable, Identifiable {
        case walking = "徒歩"
        case driving = "車"
        var id: Self { self }
        var symbol: String { self == .walking ? "figure.walk" : "car.fill" }
        var transportType: MKDirectionsTransportType { self == .walking ? .walking : .automobile }
        /// Apple マップの経路種別（w: 徒歩, d: 車, r: 電車）
        var appleMapsFlag: String { self == .walking ? "w" : "d" }
    }

    private(set) var destination: Shop?
    private(set) var route: MKRoute?
    private(set) var mode: Mode = .walking
    private(set) var isCalculating = false
    private(set) var errorMessage: String?
    /// 増えるたびに、地図が経路（または目的地）全体が見える位置に移動する
    private(set) var fitRequest = 0

    func setDestination(_ shop: Shop) {
        destination = shop
        route = nil
        errorMessage = nil
        Task { await calculate() }
    }

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        Task { await calculate() }
    }

    func clear() {
        destination = nil
        route = nil
        errorMessage = nil
    }

    private func calculate() async {
        guard let target = destination else { return }
        isCalculating = true
        defer { isCalculating = false }

        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: target.coordinate))
        request.transportType = mode.transportType

        do {
            let response = try await MKDirections(request: request).calculate()
            guard destination?.id == target.id else { return } // 途中で目的地が変わった
            route = response.routes.first
            errorMessage = route == nil ? "経路が見つかりませんでした" : nil
        } catch {
            guard destination?.id == target.id else { return }
            route = nil
            errorMessage = "経路を計算できませんでした。位置情報の許可や通信を確認してください。"
        }
        fitRequest += 1
    }

    /// 選んだ地図アプリでナビを始める URL
    func navigationURL(app: MapApp, transit: Bool = false) -> URL? {
        guard let d = destination else { return nil }
        return app.directionsURL(latitude: d.latitude, longitude: d.longitude,
                                 mode: transit ? .transit : (mode == .walking ? .walking : .driving))
    }
}

/// ナビや店の表示に使う地図アプリ（設定に保存）
enum MapApp: String, CaseIterable, Identifiable {
    case apple = "Apple マップ"
    case google = "Google マップ"
    var id: Self { self }
    static let storageKey = "mapApp"

    enum Travel { case walking, driving, transit }

    /// 経路案内の URL。Google マップはアプリが入っていればアプリ、なければブラウザで開く
    func directionsURL(latitude: Double, longitude: Double, mode: Travel) -> URL? {
        let dest = "\(latitude),\(longitude)"
        switch self {
        case .apple:
            let flag: String
            switch mode { case .walking: flag = "w"; case .driving: flag = "d"; case .transit: flag = "r" }
            return Self.url("https://maps.apple.com/", ["daddr": dest, "dirflg": flag])
        case .google:
            let travel: String
            switch mode { case .walking: travel = "walking"; case .driving: travel = "driving"; case .transit: travel = "transit" }
            return Self.url("https://www.google.com/maps/dir/", ["api": "1", "destination": dest, "travelmode": travel])
        }
    }

    /// 店の場所を表示する URL
    func placeURL(name: String, latitude: Double, longitude: Double) -> URL? {
        switch self {
        case .apple:
            return Self.url("https://maps.apple.com/", ["q": name, "ll": "\(latitude),\(longitude)"])
        case .google:
            return Self.url("https://www.google.com/maps/search/", ["api": "1", "query": "\(latitude),\(longitude)"])
        }
    }

    private static func url(_ base: String, _ items: [String: String]) -> URL? {
        var c = URLComponents(string: base)
        c?.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c?.url
    }
}

/// どのタブを表示しているか（店の詳細から「目的地に設定」したとき地図に戻るため）
@Observable
final class AppRouter {
    enum Tab: Hashable { case map, visits, settings }
    var tab: Tab = .map
}

extension TimeInterval {
    /// 12分 / 1時間5分 のような表示
    var travelTimeText: String {
        let minutes = Int((self / 60).rounded())
        if minutes < 60 { return "\(max(minutes, 1))分" }
        return "\(minutes / 60)時間\(minutes % 60 == 0 ? "" : "\(minutes % 60)分")"
    }
}
