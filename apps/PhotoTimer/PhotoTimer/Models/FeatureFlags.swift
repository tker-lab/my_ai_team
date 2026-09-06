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
/// 【2026-09-06 CEO決定(Codexとも相談し確定):有料にする機能が4つに確定】
/// 演出パターン・自作リスト(リスト作成)・場所での絞り込みの3つに加え、新設した
/// 「複数選択削除」を有料にした(振り返り一覧からの単体削除〔1枚ずつ〕は引き続き無料)。
/// 【訂正履歴】途中の指示で一時的に自作リストを無料に戻す変更をしたが、CEO確認の結果
/// これは仕様書側の記載ミスと判明し、自作リストは変更前と同じ有料のまま据え置くことになった。
enum FeatureFlags {
    /// 振り返り一覧の全画面プレビューから、今見ている1枚だけを削除できる機能。
    /// 無料機能として確定(2026-09-06)。複数選択削除(isBulkDeleteEnabled)とは別物で、
    /// こちらは購入状態を一切見ない。
    static var isHistoryDeletionEnabled: Bool {
        true
    }

    /// 振り返り一覧で複数枚をチェックして選び、まとめて削除する機能
    /// (削除モードへの切り替え・全選択・全解除・一括削除・一括削除前の確認)。
    /// 有料機能(2026-09-06 CEO決定)。購入状態(PurchaseManager)を見て判定する。
    /// 【isHistoryDeletionEnabledとの違い】上のisHistoryDeletionEnabledは「1枚だけ削除する」
    /// 無料機能を指す。こちらは「複数選び一括削除する」有料機能を指す。片方が塞がっても
    /// もう片方が動くよう、必ず別々のフラグで判定すること。
    static var isBulkDeleteEnabled: Bool { PurchaseManager.shared.isPremiumUnlocked }

    /// タイマー終了後の振り返り一覧。無料機能として確定(2026-09-06)。
    static var isSessionHistoryEnabled: Bool { true }

    /// 自作リスト(写真ライブラリから自分で選んだ写真をリスト化し、絞り込み条件として使う機能)。
    /// 有料機能(2026-09-06 CEO決定。据え置き)。購入状態(PurchaseManager)を見て判定する。
    static var isCustomListsEnabled: Bool { PurchaseManager.shared.isPremiumUnlocked }

    /// 演出パターン(結婚式ムービー風・スタジアムビジョン風等。「シンプル」は含まない)。
    /// 有料機能(2026-09-06 CEO決定)。購入状態(PurchaseManager)を見て判定する。
    static var isPresentationPatternsEnabled: Bool { PurchaseManager.shared.isPremiumUnlocked }

    /// 場所での絞り込み。有料機能(2026-09-06 CEO決定)。購入状態(PurchaseManager)を見て判定する。
    static var isPlaceFilterEnabled: Bool { PurchaseManager.shared.isPremiumUnlocked }
}
