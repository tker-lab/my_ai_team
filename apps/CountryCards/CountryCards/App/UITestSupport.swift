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
            // StartingCardsProvisioner(旧DeckManager)。旧キーも残しておき、
            // 過去にテスト済みの端末上に残っていても影響しないようにする。
            "hasGrantedStartingCards", "deckCardIDsByElement", "hasSeededInitialDeck",
        ]
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }

        if presetUsername {
            defaults.set("テストユーザー", forKey: "username")
        }
    }

    /// `-uiTestSeedNineCardCountry`: 全状態をリセットした上で、CO2排出量データが
    /// 無くカードが9種類しか存在しない国(モナコ)の9枚全てを所持済みにする。
    ///
    /// 何のためか: 「9枚しか存在しない国は10個目の豆知識が永遠に解放されない」
    /// バグ(2026-09-14修正)の確認用。9枚集め切った状態を毎回同じ手順で作れる
    /// ようにし、豆知識が10/10まで解放されることをUIテストで検証できるようにする。
    ///
    /// 【重要】CardDatabase(読み込み専用のカード定義データ)を先に参照するのは
    /// 問題ない。ここで触れてはいけないのはOwnedCollectionのような「所持状況」を
    /// 保持するシングルトンだけ(上のresetAllStateForTestingの注記を参照)。
    @MainActor
    static func seedNineCardCountryForTrivia() {
        resetAllStateForTesting()

        let iso3 = "MCO" // モナコ:CO2排出量データが無く、カードが9種類のみ存在する国
        let cardIDs = CardDatabase.shared.cards(forCountry: iso3).map(\.id)
        UserDefaults.standard.set(cardIDs, forKey: "ownedCardIDs")
    }
}
