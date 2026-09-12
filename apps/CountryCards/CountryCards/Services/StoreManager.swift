import Foundation
import StoreKit

/// ¥100で10連ガチャを買うためのApple課金(StoreKit)窓口。
///
/// 【動作状況の注意】StoreKitの動作確認は「Xcodeから直接実行(Run)した時だけ」
/// 有効になる(xcodebuildだけのコマンドライン実行では本物のApp Store側に
/// 問い合わせに行こうとしてしまい、Configuration.storekitが使われない。
/// PhotoTimer開発時に判明した既知の制約 — 詳細は
/// .claude/agent-memory/app-team/storekit-testing-requires-xcode-run-not-cli.md)。
/// そのため、このコード自体はビルドできることまでは確認したが、実際に
/// 「購入ボタンを押したら本当に30枚出るか」の動作確認はCEOがXcodeでRunした
/// 時に行ってもらう必要がある。
@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    /// ¥100で10連(30枚)ぶんのガチャ石を買える商品のID。
    /// App Store Connect側にも、この文字列と完全に一致する消耗型(Consumable)
    /// のApp内課金を登録する必要がある(Configuration.storekitはローカルの
    /// テスト用で、実際にストアで売るにはApp Store Connect側の登録が別途必要)。
    static let tenPullProductID = "com.aiteam.countrycards.tenpull"

    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false
    @Published private(set) var errorMessage: String?

    private init() {
        Task { await loadProduct() }
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.tenPullProductID])
            product = products.first
        } catch {
            errorMessage = "商品情報の取得に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 購入する。成功したら true を返す(呼び出し側でガチャ10連を実行する)。
    func purchaseTenPull() async -> Bool {
        guard let product else {
            errorMessage = "商品情報がまだ読み込めていません"
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    return true
                case .unverified:
                    errorMessage = "購入の検証に失敗しました"
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "承認待ちです(保護者の承認等)"
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "購入に失敗しました: \(error.localizedDescription)"
            return false
        }
    }
}
