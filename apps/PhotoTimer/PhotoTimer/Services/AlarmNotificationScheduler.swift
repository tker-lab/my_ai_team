import Foundation
import UserNotifications

/// 【CEO要望C. 2026-09-05:バックグラウンド動作】
/// アプリを閉じて(=バックグラウンドに回して)いる間、タイマーの終了に気づけるようにするための仕組み。
///
/// 【なぜ「アプリ自身のTask」ではなく「OS標準の通知(ローカル通知)」で実現するか】
/// iOSは、特別な許可(音楽アプリ向けの「バックグラウンドオーディオ」等)を持たないアプリを
/// バックグラウンドに回すと、数十秒ほどで実際の処理を一時停止させる。そのため、タイマーが
/// 数分先に終わる場合、アプリ自身の`Task.sleep`だけに頼っていては「バックグラウンドの間、
/// 本当に指定した時刻に鳴る」ことを保証できない。
/// ローカル通知(`UNUserNotificationCenter`)は「何時何分に、こういう通知を出す」ことをOS側に
/// 事前に予約しておく仕組みで、アプリのプロセスが一時停止・終了していてもOSが責任を持って
/// 指定時刻に届けてくれる(iPhone標準の「時計」アプリのタイマー・アラームも同じ仕組みを使っている)。
/// このアプリは「裏にいる間は解析・表示をしない」設計方針のため、バックグラウンド処理を頑張って
/// 継続させる方向ではなく、OSに「時刻になったら教えて」と予約しておくだけ、という設計にしている。
///
/// 【何が完全に再現できないか(正直な制限)】
/// 通知の音は「1回だけ」再生される仕組みのため、設定画面で選べる「n回鳴らす/止めるまで鳴り続ける」
/// という繰り返しパターンや、バイブレーションの繰り返しは、バックグラウンド中は再現できない。
/// アプリがフォアグラウンドに戻ってきた瞬間には、これまで通りの繰り返しパターンで
/// (`TimerController.playAlarm()`)しっかり鳴らし直す。「バックグラウンドでも音が鳴ること」
/// 自体は満たしつつ、繰り返し等の細かい体験はフォアグラウンド復帰時に補う、という役割分担にしている。
enum AlarmNotificationScheduler {
    /// 通知が来た時に区別できるよう固定のIDを使う(1つのタイマーにつき常に1件だけ存在する想定なので、
    /// 複数同時に予約する必要はなく、同じIDへの再予約が自然に「古い予約の上書き」になる)。
    private static let requestIdentifier = "PhotoTimer.AlarmNotification"

    /// タイマー開始時に呼ぶ。まだ通知の許可を尋ねたことが無ければここで尋ね、許可されていれば
    /// `fireDate` の時刻に鳴るよう1件だけ予約する。
    ///
    /// 【許可を求めるタイミングをアプリ起動時ではなくここにした理由】
    /// 「バックグラウンドでも鳴ってほしい」という体験に直接関係する操作(タイマー開始)の直前に
    /// 尋ねたほうが、ユーザーにとって「なぜこの許可が必要か」が伝わりやすい
    /// (アプリを開いた瞬間にいきなり尋ねられても、何のための許可か分かりにくい)。
    static func scheduleAlarm(fireDate: Date, tone: AlarmTonePattern) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                schedule(fireDate: fireDate, tone: tone, center: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        schedule(fireDate: fireDate, tone: tone, center: center)
                    }
                    // 拒否された場合は何もしない(フォアグラウンドでの通常のアラームは引き続き機能する。
                    // バックグラウンド中だけ気づけない可能性がある、という制限がユーザーの選択の結果として残る)。
                }
            case .denied, .ephemeral:
                break
            @unknown default:
                break
            }
        }
    }

    /// タイマーを早期に閉じた・タイマーが(フォアグラウンドで)無事終了した時に呼ぶ。
    /// 予約していた通知を取り消す(=バックグラウンドに一切回さなかった場合や、フォアグラウンドの
    /// まま普通に終わった場合に、後から余計な通知が届かないようにする)。
    static func cancelPendingAlarm() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
    }

    private static func schedule(fireDate: Date, tone: AlarmTonePattern, center: UNUserNotificationCenter) {
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return } // すでに過ぎている時刻には予約できない(=フォアグラウンドで即終了する場合はそもそも不要)

        let content = UNMutableNotificationContent()
        content.title = "写真タイマー"
        content.body = "設定した時間が終了しました。"
        // 音色(ピピピ/ベル/サイレン)にできるだけ寄せた通知音を鳴らす。
        // NotificationSoundFiles.swiftで端末内(Library/Sounds)に書き出したファイルを指す。
        // 書き出しに失敗していた場合(極めて稀)はOS既定の通知音にフォールバックする。
        if let soundName = NotificationSoundFiles.soundName(for: tone) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        } else {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
        // 同じIDで予約し直すと、UNUserNotificationCenterが自動的に前回分を置き換えてくれる
        // (先に明示的に消してから足す必要はない)。
        center.add(request)
    }
}
