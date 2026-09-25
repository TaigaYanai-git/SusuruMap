import CoreLocation
import Observation

/// 現在地。店までの距離や「近くの店」に使う。
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50 // 50m 動いたら更新（電池の節約）
        manager.headingFilter = 5   // 向きは5度変わったら更新
        authorization = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// 許可を求め、許可済みなら位置の取得を始める
    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        startHeading()
    }

    /// ナビ中は位置を細かく（5m ごと・高精度で）取る。終わったら電池を節約する設定に戻す
    func setNavigating(_ on: Bool) {
        manager.desiredAccuracy = on ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = on ? 5 : 50
    }

    /// 端末の向き（コンパス）の取得を始める。地図の青い点に「向いている方向」の扇形が出る
    private func startHeading() {
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    /// 現在地から店までの距離（m）。現在地が分からなければ nil
    func distance(to shop: Shop) -> CLLocationDistance? {
        location?.distance(from: CLLocation(latitude: shop.latitude, longitude: shop.longitude))
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isAuthorized {
                self.manager.startUpdatingLocation()
                self.startHeading()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.location = last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 屋内などで一時的に取れないことがあるので、何もしない（次の更新を待つ）
    }
}

extension CLLocationDistance {
    /// 850 m / 1.2 km のような表示
    var distanceText: String {
        Measurement(value: self, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
