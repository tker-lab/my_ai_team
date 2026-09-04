import Foundation

/// アラーム(タイマー終了時の音)の鳴らし方の設定。CEO要望(2026-09-05)により追加。
/// 「このピピピだと気づかない。止めるまで鳴り続けるのと、n回鳴って終わるのを選べるといい」という
/// 実機での声を受け、音色・鳴らし方・バイブレーションの有無を設定画面から選べるようにした。
/// UserDefaultsにJSONで保存し、次回起動時も同じ設定を復元する(外部への送信はしない)。
struct AlarmSettings: Codable, Equatable {
    var tone: AlarmTonePattern = .beep
    var repeatMode: AlarmRepeatMode = .times(5)
    /// バイブレーションも併用するか。既定でオン。
    /// (バイブレーションは消音スイッチの影響を受けない。「設定→サウンドと触覚→消音時のバイブレーション」
    /// が端末側でオフになっている場合だけは、アプリ側からは検知・変更できず振動しない)
    var useVibration: Bool = true

    static let `default` = AlarmSettings()
}

/// 鳴らし方。iPhone標準の「時計」アプリと同じく、
///  - n回鳴らして自動的に止まる
///  - 止めるまで(画面のボタンを押すまで)鳴り続ける
/// の2系統を用意する。
enum AlarmRepeatMode: Codable, Equatable, Hashable {
    /// 選んだ音(1サイクル)をn回繰り返して自動的に止まる。
    case times(Int)
    /// 止めるまで鳴り続ける(スライドショー画面のボタンで止める)。iPhone標準アラームと同じ挙動。
    case untilStopped
}

enum AlarmSettingsChoices {
    /// 「回数を指定」で選べるn回の値。
    static let repeatCounts: [Int] = [3, 5, 10, 20]
}

// MARK: - 永続化
enum AlarmSettingsStore {
    private static let key = "PhotoTimer.AlarmSettings.v1"

    static func load() -> AlarmSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AlarmSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: AlarmSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
