import Foundation

/// 「今まさに動いているタイマー」を端末内に記録しておくための状態。
///
/// 【なぜ必要か(CEO要望C. 2026-09-05:バックグラウンド動作)】
/// アプリをバックグラウンドに回している間に、iOSの都合でアプリのプロセスごと終了させられてしまう
/// ことがある(メモリ不足時など)。この場合、次にアプリを開いた時には「新しく開いた」のと
/// 見分けが付かない状態になるが、CEOの要望は「戻ってきたらしっかり表示すること」なので、
/// タイマーが動いていたことと、あと何秒残っていたかを端末内に覚えておき、次に開いた瞬間に
/// スライドショー画面を自動的に再開できるようにする。
///
/// 【アラーム音そのものは別の仕組み(AlarmNotificationScheduler)が担う】
/// この状態はあくまで「表示を正しく再開するための記録」であり、バックグラウンド中に指定時刻に
/// 音を鳴らす仕組みそのものはローカル通知(AlarmNotificationScheduler)が別に担当している
/// (アプリのプロセスが終了していても、ローカル通知はOS側の責任で届く)。
struct RunningTimerState: Codable {
    /// タイマーが終わる予定の時刻(絶対時刻。これを基準に「あと何秒か」を計算し直す)。
    var endDate: Date
    var totalSeconds: Int
    var filterSettings: FilterSettings
    var playbackSettings: PlaybackSettings
    var alarmSettings: AlarmSettings
}

enum RunningTimerStateStore {
    /// このぶんだけ古い記録は「もう再開する意味が無い(相当前にアラームは鳴り終わっているはず)」
    /// とみなして無視する。iPhone標準の「時計」アプリのタイマーも同様に、あまりに古いタイマーの
    /// 通知を後から開いても、延々と昔のタイマー画面には連れて行かれない、という考え方に合わせている。
    private static let staleThreshold: TimeInterval = 24 * 60 * 60 // 24時間

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("running_timer_state.json")
        // filterSettings(場所の絞り込みなど)を含むため、他の設定ファイルと同様にバックアップ対象外にする。
        BackupExclusion.exclude(url)
        return url
    }()

    static func save(_ state: RunningTimerState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
        BackupExclusion.exclude(fileURL)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 再開する価値がある記録だけを返す(古すぎる記録は消してnilを返す)。
    static func loadIfFresh() -> RunningTimerState? {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(RunningTimerState.self, from: data) else {
            return nil
        }
        let elapsedSinceEnd = Date().timeIntervalSince(decoded.endDate)
        guard elapsedSinceEnd < staleThreshold else {
            clear()
            return nil
        }
        return decoded
    }
}
