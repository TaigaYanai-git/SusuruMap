import SwiftUI
import SwiftData

@main
struct SusuruMapApp: App {
    @State private var services: AppServices
    @State private var shopStore = ShopStore()
    @State private var location = LocationProvider()
    @State private var planner = RoutePlanner()
    @State private var router = AppRouter()

    init() {
        _services = State(initialValue: AppServices.make())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .environment(shopStore)
                .environment(location)
                .environment(planner)
                .environment(router)
        }
        // 訪問記録は SwiftData に保存。iCloud(CloudKit) の entitlement を有効にすると
        // 自分の iPhone / iPad 間で自動同期される（README「iCloud同期」参照）。
        .modelContainer(for: Visit.self)
    }
}

struct RootView: View {
    @Environment(ShopStore.self) private var shopStore
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            MapScreen()
                .tabItem { Label("マップ", systemImage: "map") }
                .tag(AppRouter.Tab.map)
            VisitLogView()
                .tabItem { Label("行った店", systemImage: "checkmark.seal") }
                .tag(AppRouter.Tab.visits)
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
        .task { await shopStore.load() }
    }
}
