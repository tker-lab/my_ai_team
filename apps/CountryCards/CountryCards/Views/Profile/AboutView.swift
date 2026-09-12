import SwiftUI

/// このアプリについて・データの出典を見せる画面。
/// チェック工程指摘:出典を確認できる画面が無かったため追加(2026-09-13)。
struct AboutView: View {
    @ObservedObject private var database = CardDatabase.shared

    var body: some View {
        List {
            Section("対象範囲") {
                Text(database.note)
                    .font(.footnote)
            }

            Section("データの出典") {
                sourceRow(
                    title: "世界銀行(World Bank Open Data)",
                    detail: "人口・GDP・平均寿命など8要素の数値。無料・登録不要のAPIを使用。"
                )
                sourceRow(
                    title: "Wikidata",
                    detail: "国連加盟193カ国のリスト。"
                )
                sourceRow(
                    title: "countries.dev(REST Countries互換の無料データ)",
                    detail: "公用語の数・隣接国の数。本家REST Countries(v5)はアカウント登録が必要になったため、キー不要な代替データを暫定的に使用しています。"
                )
                sourceRow(
                    title: "flagcdn.com",
                    detail: "国旗の画像。"
                )
            }

            if let updated = database.worldBankLastUpdated {
                Section("データの更新日") {
                    Text("世界銀行データの最終更新日: \(updated)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("カードのデータは年1回程度、アプリの更新で反映します。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("生成日: \(database.generatedAt)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("このアプリについて")
    }

    private func sourceRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
