import AVFoundation
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

    // ── アプリ内ナビ ─────────────────────────────
    private(set) var isNavigating = false
    /// 次に曲がる場所の案内（例「右折して国道20号に入ります」）
    private(set) var currentInstruction: String?
    private(set) var distanceToNextTurn: CLLocationDistance?
    private(set) var remainingDistance: CLLocationDistance?
    private(set) var remainingTime: TimeInterval?
    /// 到着した店（到着したら「行った！を記録しますか？」を出す）
    private(set) var arrivedAt: Shop?
    private(set) var voiceEnabled: Bool = UserDefaults.standard.object(forKey: "navVoice") as? Bool ?? true

    @ObservationIgnored private var stepIndex = 0
    @ObservationIgnored private var lastReroute = Date.distantPast
    @ObservationIgnored private let speech = AVSpeechSynthesizer()

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
        stopNavigation()
        destination = nil
        route = nil
        errorMessage = nil
    }

    // MARK: - アプリ内ナビ

    /// 案内が出る曲がり角だけ（出発地点の空の案内などは除く）
    private var steps: [MKRoute.Step] {
        route?.steps.filter { !$0.instructions.isEmpty } ?? []
    }

    func startNavigation() {
        guard route != nil else { return }
        isNavigating = true
        arrivedAt = nil
        stepIndex = 0
        refreshInstruction()
        speak("ナビを開始します。" + (currentInstruction ?? ""))
    }

    func stopNavigation() {
        isNavigating = false
        currentInstruction = nil
        distanceToNextTurn = nil
        remainingDistance = nil
        remainingTime = nil
        speech.stopSpeaking(at: .immediate)
    }

    func clearArrival() { arrivedAt = nil }

    func toggleVoice() {
        voiceEnabled.toggle()
        UserDefaults.standard.set(voiceEnabled, forKey: "navVoice")
        if !voiceEnabled { speech.stopSpeaking(at: .immediate) }
    }

    /// 現在地が変わるたびに呼ぶ。曲がり角を過ぎたら次の案内へ、道を外れたら経路を探し直す
    func update(with here: CLLocation) {
        guard isNavigating, let route, let dest = destination else { return }

        // 到着（店まで 30m 以内）
        if here.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude)) < 30 {
            stopNavigation()
            arrivedAt = dest
            speak("目的地、\(dest.name)に到着しました")
            return
        }

        // 曲がり角（次の案内の地点）まで 20m 以内に来たら、その次の案内へ
        let steps = self.steps
        while stepIndex < steps.count,
              let start = steps[stepIndex].polyline.firstCoordinate,
              here.distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude)) < 20 {
            stepIndex += 1
            refreshInstruction()
            if let next = currentInstruction { speak(next) }
        }

        // 残りの距離と時間
        var remaining: CLLocationDistance = 0
        if stepIndex < steps.count, let start = steps[stepIndex].polyline.firstCoordinate {
            let toTurn = here.distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude))
            distanceToNextTurn = toTurn
            remaining = toTurn + steps[stepIndex...].reduce(0) { $0 + $1.distance }
        } else {
            distanceToNextTurn = nil
            remaining = here.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
        }
        remainingDistance = remaining
        if route.distance > 0 {
            remainingTime = route.expectedTravelTime * remaining / route.distance
        }

        // 経路から 60m 以上外れたら、探し直す（20秒に1回まで）
        if route.polyline.distance(to: here.coordinate) > 60, Date().timeIntervalSince(lastReroute) > 20 {
            lastReroute = Date()
            speak("ルートを再検索します")
            Task { await calculate(fit: false) }
        }
    }

    private func refreshInstruction() {
        let steps = self.steps
        currentInstruction = stepIndex < steps.count ? steps[stepIndex].instructions : "目的地はまもなくです"
    }

    private func speak(_ text: String) {
        guard voiceEnabled, !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        speech.speak(utterance)
    }

    private func calculate(fit: Bool = true) async {
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
            if isNavigating {
                stepIndex = 0
                refreshInstruction()
            }
        } catch {
            guard destination?.id == target.id else { return }
            route = nil
            errorMessage = "経路を計算できませんでした。位置情報の許可や通信を確認してください。"
        }
        if fit { fitRequest += 1 }
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
    /// アプリの中で道案内する（徒歩・車）。電車と「地図アプリで開く」は Apple マップを使う
    case inApp = "すするマップ"
    case apple = "Apple マップ"
    case google = "Google マップ"
    var id: Self { self }
    static let storageKey = "mapApp"

    /// 外部アプリで開くときに使うアプリ（すするマップを選んでいるときは Apple マップ）
    var externalApp: MapApp { self == .inApp ? .apple : self }

    enum Travel { case walking, driving, transit }

    /// 経路案内の URL。Google マップはアプリが入っていればアプリ、なければブラウザで開く
    func directionsURL(latitude: Double, longitude: Double, mode: Travel) -> URL? {
        let dest = "\(latitude),\(longitude)"
        switch self {
        case .apple, .inApp:
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
        case .apple, .inApp:
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

extension MKPolyline {
    var firstCoordinate: CLLocationCoordinate2D? {
        pointCount > 0 ? points()[0].coordinate : nil
    }

    /// ある地点から、この線（経路）までのいちばん近い距離（m）
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let p = MKMapPoint(coordinate)
        let pts = points()
        guard pointCount > 1 else { return pointCount == 1 ? p.distance(to: pts[0]) : .greatestFiniteMagnitude }
        var best = CLLocationDistance.greatestFiniteMagnitude
        for i in 0..<(pointCount - 1) {
            let a = pts[i], b = pts[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            best = min(best, p.distance(to: MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)))
        }
        return best
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
