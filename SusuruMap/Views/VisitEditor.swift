import SwiftUI
import SwiftData

/// 記録済みの「行った！」の日付・メモを後から変える（削除もここから）
struct VisitEditor: View {
    let visit: Visit

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var memo: String
    @State private var confirmingDelete = false

    init(visit: Visit) {
        self.visit = visit
        _date = State(initialValue: visit.visitedAt)
        _memo = State(initialValue: visit.memo)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(visit.shopName).font(.headline)
                    DatePicker("行った日", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("メモ（頼んだメニュー、一緒に行った人など）", text: $memo, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button("この記録を削除", role: .destructive) { confirmingDelete = true }
                }
            }
            .navigationTitle("訪問記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        visit.visitedAt = date
                        visit.memo = memo.trimmed
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("この訪問記録を削除しますか？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    context.delete(visit)
                    try? context.save()
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
