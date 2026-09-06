import SwiftUI

/// 「Q&A」画面。CEO要望(2026-09-06)により、以前の「使い方・仕組み」の説明文を
/// Q&A形式に全面差し替え。文面はCEOが用意したものをそのまま使用している。
/// ホーム画面右上の「?」からいつでも見返せるようにしている(初回だけでなく後からでも確認できるように)。
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    /// 見出し・説明文の字体をテーマに合わせるために参照する(CEO要望・2026-09-06)。
    @AppStorage(AppThemeStore.key) private var themeRawValue: String = AppTheme.default.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .default }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    qa(question: "写真が外に漏れちゃったりしない？",
                       answer: "写真の判定処理は全て端末内で行われます。\n広告なども付けていないため、外部との通信はございませんのでご安心下さい。")
                    qa(question: "写真切り替え時間が設定より遅いです",
                       answer: "都度絞り込み条件に近い写真を探し回っています。\n写真数が多いor対象写真が少ないと表示に時間がかかる事があります。\nセキュリティ重視で全て端末内で処理しているためお許し下さい。")
                    qa(question: "絞り込み条件と違う写真が結構出ます",
                       answer: "高性能なAIなどは\"あえて\"搭載してません。\n少し違う写真とも一期一会の出会いをお楽しみください。\nつまり、高性能なAIを搭載するお金はありませんと言う事です。")
                    qa(question: "よく撮れてる度って何？",
                       answer: "iOS18以降に標準搭載されている機能です。\n優先であって除外ではないのでよく撮れてない写真が入る場合もあります。\nきっとあなたが笑顔で写っている写真がたくさん表示されるはずです。")
                    qa(question: "BGMとか無いの？",
                       answer: "そのような機能はございません。\nApple Musicなどをバックグラウンドで流していただければ、フリーBGMより良いものになるでしょう。\nつまり、いい感じのフリー音源を探すのが面倒だったということです。")
                } header: {
                    Text("標準搭載機能について").fontDesign(theme.fontDesign)
                }

                Section {
                    qa(question: "写真を間違って削除してしまいました。",
                       answer: "iPhoneの写真アプリに「最近削除した項目」というのがございます。\n30日以内であればそちらから復元できますのでご安心ください。")
                    qa(question: "流した映像を保存したい",
                       answer: "申し訳ないですがそのような機能はございません。\niPhoneにある画面録画でご対応ください。\nつまり、保存する行為は権利の問題があってややこしいということです。")
                } header: {
                    Text("課金コンテンツについて").fontDesign(theme.fontDesign)
                }
            }
            .themedFormBackground()
            .themedFontDesign()
            .navigationTitle("Q&A")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("閉じる").fontDesign(theme.fontDesign) }
                }
            }
        }
    }

    /// 1つのQ&Aを1つのカードのようなまとまりとして見せる共通パーツ。
    private func qa(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.headline)
                .fontDesign(theme.fontDesign)
            Text(answer)
                .font(.subheadline)
                .fontDesign(theme.fontDesign)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
