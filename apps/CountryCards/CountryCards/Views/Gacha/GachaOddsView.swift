import SwiftUI

/// ガチャの排出確率を表示する画面。
///
/// App Storeの審査ガイドライン3.1.1は「課金で引けるガチャは、購入前に実際の
/// 確率を開示すること」を義務付けている。この画面をガチャ画面・¥100購入画面・
/// ポイントガチャ画面から見られるようにすることで、その要件を満たす
/// (チェック工程で指摘され2026-09-13に追加)。
///
/// 【2026-09-13 再チェックでの指摘】「10連の最後の1枚」の保証内容は
/// 引き方によって違う(¥100の10連=SSR以上確定、ポイントの10連=SR以上確定、
/// ポイントの100連=SSR以上確定)。以前は¥100の10連の内容だけを常に表示して
/// いたため、ポイントガチャ経由で見たユーザーが誤解する恐れがあった。
/// `source`でどの入り口から開いたかを受け取り、該当する保証だけを出す。
struct GachaOddsView: View {
    /// どの入り口(画面)から開かれたか。保証内容の表示を出し分けるために使う。
    enum Source {
        /// ガチャ画面トップの共通入り口(特定の引き方に紐付かない)。
        case general
        /// ¥100のIAP購入画面から(10連=SSR以上確定のみ)。
        case iapTenPull
        /// ダブりポイントの画面から(10連=SR以上確定・100連=SSR以上確定)。
        case point
    }

    var source: Source = .general

    var body: some View {
        List {
            Section("1・2枚目の確率") {
                oddsRow("N", "70%")
                oddsRow("SR", "22%")
                oddsRow("SSR", "6%")
                oddsRow("UR", "2%")
            }
            Section("3枚目(SR以上確定)の内訳") {
                oddsRow("SR", "82%")
                oddsRow("SSR", "15%")
                oddsRow("UR", "3%")
            }

            guaranteeSection

            Section("超激レア「北朝鮮のGDP」(HUR)") {
                Text("1/20,000,000")
                Text("上記のすべての抽選より前に判定され、当たった場合はそのカードになります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("ダブりポイントで引くガチャも、レア度が決まる確率は上と全く同じです(未所持のカードが選ばれやすくなるのは、レア度が決まった後の「どの国のカードか」の抽選だけです)。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("排出確率")
    }

    /// まとめ買いの最後の1枚の保証内容。`source`によって、実際に当てはまる
    /// ものだけを見せる(¥100とポイントでは保証の強さが違うため)。
    @ViewBuilder
    private var guaranteeSection: some View {
        switch source {
        case .general:
            Section("¥100の10連(30枚)の最後の1枚(30枚目)") {
                Text("SSR以上確定")
                ssrPlusBreakdown
            }
            Section("ポイントの10連(30枚)の最後の1枚(30枚目)") {
                Text("SR以上確定")
                srPlusBreakdown
            }
            Section("ポイントの100連(300枚)の最後の1枚(300枚目)") {
                Text("SSR以上確定")
                ssrPlusBreakdown
            }
        case .iapTenPull:
            Section("この10連(30枚)の最後の1枚(30枚目)") {
                Text("SSR以上確定")
                ssrPlusBreakdown
            }
        case .point:
            Section("ポイントの10連(30枚)の最後の1枚(30枚目)") {
                Text("SR以上確定")
                srPlusBreakdown
            }
            Section("ポイントの100連(300枚)の最後の1枚(300枚目)") {
                Text("SSR以上確定")
                ssrPlusBreakdown
            }
        }
    }

    private var srPlusBreakdown: some View {
        Group {
            oddsRow("SR", "82%")
            oddsRow("SSR", "15%")
            oddsRow("UR", "3%")
        }
    }

    private var ssrPlusBreakdown: some View {
        Group {
            oddsRow("SSR", "75%")
            oddsRow("UR", "25%")
        }
    }

    private func oddsRow(_ label: String, _ percent: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(percent).foregroundStyle(.secondary)
        }
    }
}
