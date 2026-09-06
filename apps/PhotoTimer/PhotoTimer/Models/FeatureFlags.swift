import Foundation

/// アプリ全体の機能フラグ(オン/オフ切り替え)を1箇所にまとめる。
///
/// 【なぜこのファイルを作ったか】CEO要望(2026-09-05):「写真の削除機能を、将来的に課金者限定に
/// する可能性を検討している。後から切り分けやすい作りにしておいてほしい」への対応。
/// 削除ボタンを出すかどうかの判定を、SlideshowView(画面側のコード)に直接
/// 「trueで固定」のように埋め込んでしまうと、後で「課金していない人には見せない」という条件に
/// 変えたくなった時、画面のコードのあちこちを探して直す必要が出てくる。
/// 代わりに、判定そのものをこの1つの計算プロパティに集約しておけば、将来的に
/// 「課金状態を見て判定する」のように、この関数の中身だけを書き換えれば済む
/// (呼び出し側=SlideshowView等は一切変更不要)。
///
/// 【2026-09-06 CEO決定:有料にする機能が3つに確定】演出パターン・自作リスト(リスト作成)・
/// 場所での絞り込みの3つを、`PurchaseManager`(StoreKit 2で購入状態を管理する)を見て
/// 判定するように変更した。削除機能・振り返り一覧は無料機能として確定したため、
/// 引き続き常にtrueのまま。
enum FeatureFlags {
    /// 振り返り一覧から写真・動画を削除できる機能。無料機能として確定(2026-09-06)。
    static var isHistoryDeletionEnabled: Bool {
        true
    }

    /// タイマー終了後の振り返り一覧。無料機能として確定(2026-09-06)。
    static var isSessionHistoryEnabled: Bool { true }

    /// 自作リスト(写真ライブラリから自分で選んだ写真をリスト化し、絞り込み条件として使う機能)。
    /// 有料機能(2026-09-06 CEO決定)。購入状態(PurchaseManager)を見て判定する。
    static var isCustomListsEnabled: Bool { PurchaseManager.shared.isPremiumUnlocked }

    /// 演出パターン(結婚式ムービー風・スタジアムビジョン風等。「シンプル」は含まない)。
    /// 有料機能(2026-09-06 CEO決定)。購入状態(PurchaseManager)を見て判定する。
    static var isPresentationPatternsEnabled: Bool { PurchaseManager.shared.isPremiumUnlocked }

    /// 場所での絞り込み。有料機能(2026-09-06 CEO決定)。購入状態(PurchaseManager)を見て判定する。
    static var isPlaceFilterEnabled: Bool { PurchaseManager.shared.isPremiumUnlocked }
}
