import SwiftUI

/// このアプリについて・データの出典を見せる画面。
/// チェック工程指摘:出典を確認できる画面が無かったため追加(2026-09-13)。
struct AboutView: View {
    @ObservedObject private var database = CardDatabase.shared

    var body: some View {
        ZStack { EarthBackdrop(variant: .profile); ScrollView { VStack(spacing: 14) {
            ArchivePanel { VStack(alignment: .leading, spacing: 8) { Text("対象範囲").font(.headline); Text(database.note).font(.footnote) } }
            ArchivePanel { VStack(alignment: .leading, spacing: 14) { Text("データの出典").font(.headline)
                sourceRow(
                    title: "世界銀行(World Bank Open Data)",
                    detail: "人口・GDP・平均寿命など8要素の数値。無料・登録不要のAPIを使用。"
                )
                sourceRow(
                    title: "Wikidata",
                    detail: "国連加盟193カ国のリスト。"
                )
                sourceRow(
                    title: "REST Countries",
                    detail: "公用語の数・陸続きの隣接国の数に使用しています。"
                )
                sourceRow(
                    title: "flagcdn.com",
                    detail: "国旗の画像。"
                )
            } }

            if let updated = database.worldBankLastUpdated {
                ArchivePanel { VStack(alignment: .leading, spacing: 8) { Text("データの更新日").font(.headline)
                    Text("世界銀行データの最終更新日: \(updated)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("カードのデータは年1回程度、アプリの更新で反映します。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } }
            }
            Text("生成日: \(database.generatedAt)").font(.caption2).foregroundStyle(EarthColors.secondary)
        }.padding() } }
        .earthNavigationTitle("このアプリについて")
    }

    private func sourceRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
