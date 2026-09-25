import SwiftUI
import SwiftData

/// 行った店の一覧と制覇率
struct VisitLogView: View {
    @Environment(ShopStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \Visit.visitedAt, order: .reverse) private var visits: [Visit]

    var body: some View {
        let visitedShopIDs = Set(visits.map(\.shopId))
        let conquered = store.shops.filter { visitedShopIDs.contains($0.id) }.count
        let total = max(store.shops.count, 1)

        NavigationStack {
            List {
                Section("制覇率") {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: Double(conquered), total: Double(total))
                            .tint(.orange)
                        Text("\(conquered) / \(store.shops.count) 店（\(Int(Double(conquered) / Double(total) * 100))%）・通算 \(visits.count) 杯")
                            .font(.subheadline)
                    }
                }
                if !visits.isEmpty {
                    Section("訪問履歴") {
                        ForEach(visits) { visit in
                            if let shop = store.shop(id: visit.shopId) {
                                NavigationLink(value: shop) { row(visit) }
                            } else {
                                row(visit)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { context.delete(visits[i]) }
                        }
                    }
                }
            }
            .overlay {
                if visits.isEmpty {
                    ContentUnavailableView("まだ記録がありません",
                                           systemImage: "fork.knife",
                                           description: Text("マップで店を選んで「行った！」を記録しましょう"))
                }
            }
            .navigationTitle("行った店")
            .navigationDestination(for: Shop.self) { ShopDetailView(shop: $0) }
        }
    }

    private func row(_ visit: Visit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(visit.shopName).font(.headline)
            Text(visit.visitedAt.formatted(date: .long, time: .omitted))
                .font(.caption).foregroundStyle(.secondary)
            if !visit.memo.isEmpty {
                Text(visit.memo).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}
