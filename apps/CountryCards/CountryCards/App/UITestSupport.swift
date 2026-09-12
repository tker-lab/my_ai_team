import Foundation

/// UIテスト専用のリセット処理。`-uiTestReset` 起動引数が付いた時だけ
/// CountryCardsApp.init()から呼ばれる。本番の起動経路には一切関わらない。
///
/// なぜ必要か: DailyBonusManager導入(1日の無料ガチャ回数制限)により、
/// 同じシミュレーターでUIテストを何度も実行すると「今日はもうログイン
/// ボーナスを受け取り済み」の状態が残り、無料ガチャが枯渇してテストが
/// 不安定になる。各テストの実行前にセーブデータを完全に空へ戻すことで、
/// 何度実行しても同じ条件で試せるようにする。
///
/// 【重要】ここはまだどのシングルトン(OwnedCollection等)も初期化されて
/// いない、アプリ起動の一番最初(App.init())で呼ぶ前提。UserDefaultsを
/// 直接操作するだけにして、@MainActorなシングルトンには一切触れない
/// (触れてしまうと、その後の`.shared`初期化が「もう存在するインスタンス」
/// を使い回し、UserDefaultsをクリアした効果が反映されなくなるため)。
enum UITestSupport {
    /// `-uiTestReset`: セーブデータを全消去し、ユーザー名だけは登録済みにする
    /// (オンボーディング画面を毎回突破しなくて済むよう、既存のUIテスト群向け)。
    static func resetAllStateForTesting(presetUsername: Bool = true) {
        let defaults = UserDefaults.standard
        let keysToRemove = [
            // OwnedCollection
            "ownedCardIDs", "dupePoints", "username", "battleWinCount",
            "gachaUseCount", "completionDate",
            // DailyBonusManager(firstLaunchDateも消し、初回7日間ボーナスから
            // テストが始まるようにする)
            "freePullsAvailable", "firstLaunchDate", "lastLoginGrantDay",
            "adBonusDay", "adBonusCountToday", "battleBonusDay", "battleBonusCountToday",
            // DeckManager
            "deckCardIDsByElement", "hasSeededInitialDeck",
        ]
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }

        if presetUsername {
            defaults.set("テストユーザー", forKey: "username")
        }
    }
}
