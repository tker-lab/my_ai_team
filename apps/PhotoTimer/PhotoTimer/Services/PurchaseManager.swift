import Foundation
import StoreKit

/// 課金状態(購入・復元)を一手に管理するクラス。CEO決定(2026-09-06。Codexとも相談し確定):
/// 有料にする機能は「複数選択削除・場所での絞り込み・演出パターン」の3つで、個別課金にはせず
/// 1つの買い切り商品(`premiumProductID`)ですべて解放する。
///
/// 【StoreKit 2について】`Product`(商品情報を取得する型)・`Transaction`(購入結果・所有状況を
/// 表す型)・`Product.purchase()`(購入処理そのもの)というAppleの新しい課金APIを使っている。
/// 実際の決済やApple Developer Program登録が無くても、Xcodeの「StoreKitテスト」機能
/// (`Configuration.storekit`。プロジェクト内に置いた設定ファイルで、Xcode/シミュレータ・実機が
/// 本物のApp Storeの代わりにこれを参照する)を使えば、CEOの端末で無料のまま購入フローを
/// 試せる。CEOへの手順は完了報告に記載。
///
/// 【なぜクラス全体を@MainActorにしないか】`FeatureFlags.swift`の計算プロパティ
/// (isCustomListsEnabled等)から`PurchaseManager.shared.isPremiumUnlocked`を同期的に
/// 読みたいが、呼び出し元がすべてメインスレッド上とは限らないコードパスもありうるため、
/// クラス自体は@MainActorにせず、実際にAppleのAPIとやり取りする非同期メソッドだけを
/// @MainActorにしている(状態を書き換えるのは必ずメインスレッドから、という制約に絞る)。
/// これは他の箇所(ResumeBox等)で採用している「実務上の単純化を優先する」方針と同じ考え方。
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    /// 3機能をまとめて解放する買い切り商品のID。
    /// `Configuration.storekit`(StoreKitテスト用の設定ファイル)に同じIDで登録してある。
    static let premiumProductID = "com.aiteam.PhotoTimer.premiumUnlock"

    /// 購入済みかどうか。`FeatureFlags.swift`の3つの機能フラグ(複数選択削除・場所での絞り込み・
    /// 演出パターン)はすべてここを見て判定する。
    @Published private(set) var isPremiumUnlocked = false
    /// App Store(またはStoreKitテスト)から取得した商品情報。購入ボタンの表示名・価格に使う。
    @Published private(set) var product: Product?
    @Published private(set) var isLoadingProduct = false
    /// 直近のエラーメッセージ(購入画面に表示する)。判定の内部事情には触れず、
    /// 「何が起きたか」「次に何をすればよいか」だけを伝える文言にしてある。
    @Published var lastErrorMessage: String?

    /// 他の端末・他のApp(iTunesでの購入等)からの変化を継続的に受け取るための購読。
    private var transactionListenerTask: Task<Void, Never>?

    private init() {
        // 【DEBUG限定・2026-09-06追加】複数選択削除・場所での絞り込み・演出パターン自体の動作を
        // 確認する既存のUIテストは、課金機能とは無関係に「機能そのものが正しく動くか」を見たい。
        // 実際のStoreKit購入確認ダイアログ(システムUI)を自動化するのは不安定なため、
        // 他所(FilterSettingsStore.PHOTOTIMER_UI_TEST_SEARCH_BUDGET)と同じ考え方で、
        // テスト時だけ環境変数で「購入済み」を強制できるようにする(本番ビルドには影響しない)。
        #if DEBUG
        let forcePremiumForTesting = ProcessInfo.processInfo.environment["PHOTOTIMER_UI_TEST_FORCE_PREMIUM"] == "1"
        if forcePremiumForTesting {
            isPremiumUnlocked = true
        }
        #else
        let forcePremiumForTesting = false
        #endif
        transactionListenerTask = Task.detached { [weak self] in
            await self?.observeTransactionUpdates()
        }
        Task { [weak self] in
            await self?.loadProduct()
            // テスト用に強制済みの場合、実際のStoreKit所有状況で上書きしない
            // (StoreKitテスト環境では未購入のままなので、そのまま呼ぶとfalseに戻ってしまう)。
            if !forcePremiumForTesting {
                await self?.refreshEntitlement()
            }
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    /// 商品情報(表示名・価格)を取得する。購入画面が開くたびに呼んでも安全(取得済みでも上書きするだけ)。
    @MainActor
    func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [Self.premiumProductID])
            product = products.first
        } catch {
            lastErrorMessage = "商品情報を取得できませんでした。通信状況を確認し、時間をおいてもう一度お試しください。"
        }
    }

    /// 購入処理本体。CEOがStoreKitテストで実際に押して試すボタンから呼ばれる。
    @MainActor
    func purchase() async {
        guard let product else { return }
        lastErrorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // 「取引を確認済みにする」処理。これを呼ばないと、次回起動時に同じ取引が
                    // 「未処理」のまま扱われ続ける(Appleが定めた作法どおりの後始末)。
                    await transaction.finish()
                    await refreshEntitlement()
                case .unverified:
                    lastErrorMessage = "購入の確認ができませんでした。時間をおいてもう一度お試しください。"
                }
            case .userCancelled:
                break // ユーザーが自分で購入をやめただけなので、エラー表示はしない。
            case .pending:
                lastErrorMessage = "購入が保留中です(ファミリー共有の承認待ちなど)。承認され次第、自動的に反映されます。"
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = "購入処理中にエラーが発生しました。時間をおいてもう一度お試しください。"
        }
    }

    /// 「購入の復元」。機種変更等で既に購入済みのはずの人が、再度有効化するために使う
    /// (App Storeアプリの一般的な作法どおり、ボタンひとつで用意する)。
    @MainActor
    func restorePurchases() async {
        lastErrorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            lastErrorMessage = "購入の復元中にエラーが発生しました。時間をおいてもう一度お試しください。"
        }
    }

    /// 実際に「今、権利を持っているか」をAppleの記録から数え直す。購入直後・復元直後・
    /// アプリ起動時・他端末での変化を受け取った直後、いずれもこれを呼んで最新化する。
    @MainActor
    func refreshEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.premiumProductID,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }
        isPremiumUnlocked = unlocked
    }

    /// アプリがフォアグラウンドでない間に起きた変化(他端末での購入・返金処理等)を
    /// 継続的に拾い続けるための監視ループ。
    private func observeTransactionUpdates() async {
        for await update in Transaction.updates {
            if case .verified(let transaction) = update {
                await transaction.finish()
                await refreshEntitlement()
            }
        }
    }
}
