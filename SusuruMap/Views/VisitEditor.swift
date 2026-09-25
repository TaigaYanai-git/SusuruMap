import SwiftUI
import SwiftData

/// 「行った！」の記録。日付を選び、必要ならカレンダーにも登録する。
struct VisitEditor: View {
    let shop: Shop
    var onSaved: (Date) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("addVisitsToCalendar") private var addToCalendar = false

    @State private var date = Date()
    @State private var memo = ""
    @State private var isSaving = false
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(shop.name).font(.headline)
                    DatePicker("行った日", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("メモ（頼んだメニュー、一緒に行った人など）", text: $memo, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Toggle("iPhoneのカレンダーにも登録", isOn: $addToCalendar)
                } footer: {
                    Text("訪問記録は iCloud で自分の端末間に同期されます（iCloud 設定時）。")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("行った！")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved ? "閉じる" : "キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !saved {
                        Button("記録") { Task { await save() } }
                            .disabled(isSaving)
                    }
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        context.insert(Visit(shopId: shop.id, shopName: shop.name, visitedAt: date, memo: memo.trimmed))
        try? context.save()
        saved = true
        onSaved(date)

        if addToCalendar {
            do {
                try await CalendarSync.addVisit(shop: shop, date: date, memo: memo.trimmed)
            } catch {
                errorMessage = "訪問は記録しましたが、カレンダー登録に失敗しました：\(error.localizedDescription)"
                return
            }
        }
        dismiss()
    }
}
