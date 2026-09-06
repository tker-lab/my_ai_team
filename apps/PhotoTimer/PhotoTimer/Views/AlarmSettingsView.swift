import SwiftUI
import AVFAudio

/// 「タイマー終了時のアラームの鳴らし方」を設定する画面。CEO要望(2026-09-05):
/// 音色・鳴らし方(n回/止めるまで)・バイブレーションの有無を選べるようにする。
struct AlarmSettingsView: View {
    @Binding var settings: AlarmSettings
    @Environment(\.dismiss) private var dismiss

    /// 試聴中の音を保持する参照。ここで保持しないと再生の途中で解放されて無音になってしまう。
    @State private var previewPlayer: AVAudioPlayer?
    /// 見出し・説明文・ボタンの字体をテーマに合わせるために参照する(CEO要望・2026-09-06)。
    @AppStorage(AppThemeStore.key) private var themeRawValue: String = AppTheme.default.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .default }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $settings.tone) {
                        ForEach(AlarmTonePattern.allCases) { tone in
                            Text(tone.rawValue).fontDesign(theme.fontDesign).tag(tone)
                        }
                    } label: {
                        Text("音色").fontDesign(theme.fontDesign)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("alarmTonePicker")

                    Button {
                        playPreview()
                    } label: {
                        Label {
                            Text("試聴する").fontDesign(theme.fontDesign)
                        } icon: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                    }
                    .accessibilityIdentifier("alarmPreviewButton")
                } header: {
                    Text("音色").fontDesign(theme.fontDesign)
                } footer: {
                    Text("消音スイッチ(マナースイッチ)がオンの状態でもこの試聴ボタンで確認できます。聞こえない場合は、本体の音量ボタンで音量を上げてからお試しください。")
                        .fontDesign(theme.fontDesign)
                }

                Section {
                    Picker(selection: repeatModeKindBinding) {
                        Text("回数を指定").fontDesign(theme.fontDesign).tag(0)
                        Text("止めるまで鳴り続ける").fontDesign(theme.fontDesign).tag(1)
                    } label: {
                        Text("鳴らし方").fontDesign(theme.fontDesign)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("alarmRepeatModePicker")

                    if case .times = settings.repeatMode {
                        Picker(selection: repeatCountBinding) {
                            ForEach(AlarmSettingsChoices.repeatCounts, id: \.self) { n in
                                Text("\(n)回").fontDesign(theme.fontDesign).tag(n)
                            }
                        } label: {
                            Text("回数").fontDesign(theme.fontDesign)
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("alarmRepeatCountPicker")
                    }
                } header: {
                    Text("鳴らし方").fontDesign(theme.fontDesign)
                } footer: {
                    if case .untilStopped = settings.repeatMode {
                        Text("タイマーが終わると、画面のボタンを押すまで鳴り続けます(iPhone標準のアラームと同じ挙動です)。")
                            .fontDesign(theme.fontDesign)
                    } else {
                        Text("選んだ音を指定回数くり返したら自動的に鳴り止みます。画面のボタンで途中で止めることもできます。")
                            .fontDesign(theme.fontDesign)
                    }
                }

                Section {
                    Toggle(isOn: $settings.useVibration) {
                        Text("バイブレーションを使う").fontDesign(theme.fontDesign)
                    }
                        .accessibilityIdentifier("alarmVibrationToggle")
                } footer: {
                    Text("バイブレーションは消音スイッチの影響を受けません。ただし本体の「設定→サウンドと触覚→消音時のバイブレーション」がオフの場合は、アプリ側からは振動させられません。")
                        .fontDesign(theme.fontDesign)
                }
            }
            .themedFormBackground()
            .themedFontDesign()
            .navigationTitle("アラーム設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("完了").fontDesign(theme.fontDesign) }
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
