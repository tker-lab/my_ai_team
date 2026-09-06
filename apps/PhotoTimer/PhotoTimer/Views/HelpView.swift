import SwiftUI

/// 「Q&A」画面。CEO要望(2026-09-06)により、以前の「使い方・仕組み」の説明文を
/// Q&A形式に全面差し替え。文面はCEOが用意したものをそのまま使用している。
/// ホーム画面右上の「?」からいつでも見返せるようにしている(初回だけでなく後からでも確認できるように)。
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("標準搭載機能について") {
                    qa(question: "写真が外に漏れちゃったりしない？",
                       answer: "写真の判定処理は全て端末内で行われます。\n広告なども付けていないため、外部との通信はございませんのでご安心下さい。")
                    qa(question: "写真切り替え時間が設定より遅いです",
                       answer: "都度絞り込み条件に近い写真を探し回っています。\n写真数が多いor対象写真が少ないと表示に時間がかかる事があります。\nA1の通りセキュリティ重視で全て端末内で処理しているためお許し下さい。")
                    qa(question: "絞り込み条件と違う写真が結構出ます",
                       answer: "高性能なAIなどは\"あえて\"搭載してません。\n少し違う写真とも一期一会の出会いをお楽しみください。\nつまり高性能なAIを搭載するお金はありませんと言う事です。")
                    qa(question: "よく撮れてる度って何？",
                       answer: "iOS18以降に標準搭載されている機能です。\n優先であって除外ではないのでよく撮れてない写真が入る場合もあります。\nきっとあなたが笑顔で写っている写真がたくさん表示されるはずです。")
                    qa(question: "BGMとか無いの？",
                       answer: "そのような機能はございません。\nApple Musicなどをバックグラウンドで流していただければ、皆様お好みのよくあるBGMより良いものになります。\nつまり、音楽を搭載するのが面倒だったという事です。")
                }

                Section("課金コンテンツについて") {
                    qa(question: "写真を間違って削除してしまいました。",
                       answer: "iPhoneの写真アプリに「最近削除した項目」というのがございます。\n30日以内であればそちらから復元できますのでご安心ください。")
                    qa(question: "流した映像を保存したい",
                       answer: "申し訳ないですがそのような機能はございません。\niPhoneにある画面録画でご対応ください。\nつまり保存する行為は権利の問題があってややこしいということです。")
                }
            }
            .themedFormBackground()
            .themedFontDesign()
            .navigationTitle("Q&A")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    /// 1つのQ&Aを1つのカードのようなまとまりとして見せる共通パーツ。
    private func qa(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.headline)
            Text(answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
