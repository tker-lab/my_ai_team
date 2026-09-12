import SwiftUI

/// ガチャの排出確率を表示する画面。
///
/// App Storeの審査ガイドライン3.1.1は「課金で引けるガチャは、購入前に実際の
/// 確率を開示すること」を義務付けている。この画面をガチャ画面・¥100購入画面の
/// 両方から見られるようにすることで、その要件を満たす(チェック工程で指摘され
/// 2026-09-13に追加)。
struct GachaOddsView: View {
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
            Section("10連(30枚)の最後の1枚(30枚目)") {
                Text("SSR以上確定")
                oddsRow("SSR", "75%")
                oddsRow("UR", "25%")
            }
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

    private func oddsRow(_ label: String, _ percent: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(percent).foregroundStyle(.secondary)
        }
    }
}
