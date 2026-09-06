import SwiftUI
import AVFAudio

/// 「タイマー終了時のアラームの鳴らし方」を設定する画面。CEO要望(2026-09-05):
/// 音色・鳴らし方(n回/止めるまで)・バイブレーションの有無を選べるようにする。
struct AlarmSettingsView: View {
    @Binding var settings: AlarmSettings
    @Environment(\.dismiss) private var dismiss

    /// 試聴中の音を保持する参照。ここで保持しないと再生の途中で解放されて無音になってしまう。
    @State private var previewPlayer: AVAudioPlayer?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("音色", selection: $settings.tone) {
                        ForEach(AlarmTonePattern.allCases) { tone in
                            Text(tone.rawValue).tag(tone)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("alarmTonePicker")

                    Button {
                        playPreview()
                    } label: {
                        Label("試聴する", systemImage: "speaker.wave.2.fill")
                    }
                    .accessibilityIdentifier("alarmPreviewButton")
                } header: {
                    Text("音色")
                } footer: {
                    Text("消音スイッチ(マナースイッチ)がオンの状態でもこの試聴ボタンで確認できます。聞こえない場合は、本体の音量ボタンで音量を上げてからお試しください。")
                }

                Section {
                    Picker("鳴らし方", selection: repeatModeKindBinding) {
                        Text("回数を指定").tag(0)
                        Text("止めるまで鳴り続ける").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("alarmRepeatModePicker")

                    if case .times = settings.repeatMode {
                        Picker("回数", selection: repeatCountBinding) {
                            ForEach(AlarmSettingsChoices.repeatCounts, id: \.self) { n in
                                Text("\(n)回").tag(n)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("alarmRepeatCountPicker")
                    }
                } header: {
                    Text("鳴らし方")
                } footer: {
                    if case .untilStopped = settings.repeatMode {
                        Text("タイマーが終わると、画面のボタンを押すまで鳴り続けます(iPhone標準のアラームと同じ挙動です)。")
                    } else {
                        Text("選んだ音を指定回数くり返したら自動的に鳴り止みます。画面のボタンで途中で止めることもできます。")
                    }
                }

                Section {
                    Toggle("バイブレーションを使う", isOn: $settings.useVibration)
                        .accessibilityIdentifier("alarmVibrationToggle")
                } footer: {
                    Text("バイブレーションは消音スイッチの影響を受けません。ただし本体の「設定→サウンドと触覚→消音時のバイブレーション」がオフの場合は、アプリ側からは振動させられません。")
                }
            }
            .themedFormBackground()
            .themedFontDesign()
            .navigationTitle("アラーム設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    // MARK: - 鳴らし方(種類・回数)のバインディング

    private var repeatModeKindBinding: Binding<Int> {
        Binding(
            get: {
                switch settings.repeatMode {
                case .times: return 0
                case .untilStopped: return 1
                }
            },
            set: { newValue in
                switch newValue {
                case 0:
                    settings.repeatMode = .times(AlarmSettingsChoices.repeatCounts.first ?? 3)
                default:
                    settings.repeatMode = .untilStopped
                }
            }
        )
    }

    private var repeatCountBinding: Binding<Int> {
        Binding(
            get: {
                if case .times(let n) = settings.repeatMode { return n }
                return AlarmSettingsChoices.repeatCounts.first ?? 3
            },
            set: { settings.repeatMode = .times($0) }
        )
    }

    // MARK: - 試聴

    /// 選んでいる音色を1回だけ再生して確認できるようにする。
    /// タイマー終了時のアラーム(TimerController.finish())と同じ音声セッション設定を使うため、
    /// 消音スイッチがオンの状態でも「本当に聞こえるか」をここで確認できる
    /// (タイマーが終わるのを待たなくても確認できる、という副次的な利点もある)。
    private func playPreview() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = try? AVAudioPlayer(data: AlarmTone.data(for: settings.tone))
        player?.volume = 1.0
        player?.play()
        previewPlayer = player
    }
}
