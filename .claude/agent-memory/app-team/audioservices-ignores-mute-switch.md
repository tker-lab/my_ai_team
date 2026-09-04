---
name: audioservices-ignores-mute-switch
description: AudioServicesPlaySystemSoundはAVAudioSessionのカテゴリを一切見ないため、マナースイッチを無視して鳴らすアラーム音には使えない
metadata:
  type: project
---

`AudioServicesPlaySystemSound`(System Sound Services。キーボード音や送信音のような「短い操作音」向けのAPI)は、
その時点でアプリの`AVAudioSession`がどんなカテゴリ(`.playback`等)になっていても**一切参照しない**仕様。
そのため「アラームを鳴らす直前に音声セッションを`.playback`へ切り替える」という対策は効果がない —
このAPIを使っている限り、常にiPhone本体のマナースイッチ(消音スイッチ)の状態に従って鳴る/鳴らないが決まる。

PhotoTimerで「マナーモードだとアラームが鳴らない」バグの2回目の調査で判明(1回目の対応=音声セッション切替は
効果がなかった)。Appleの技術文書QA1631にも同種の注意書きがある。

**How to apply:** マナースイッチを無視して確実に音を鳴らしたいアプリ(タイマー・リマインダー・通知音等)を
作る時は、`AudioServicesPlaySystemSound`ではなく`AVAudioPlayer`(または`AVAudioEngine`)で実際の音声データを
`.playback`カテゴリのセッション下で再生すること。外部音声ファイルを同梱したくない場合、短いビープ音は
PCMサンプルを計算しWAVヘッダーを付けたDataをその場で生成すれば、追加素材なしで`AVAudioPlayer(data:)`に渡せる
(実装例: `apps/PhotoTimer/PhotoTimer/Services/AlarmTone.swift`)。
バイブレーション(`kSystemSoundID_Vibrate`)はマナースイッチの影響を受けない(受けるのは設定→サウンドと
触覚→「消音時のバイブレーション」がオフの場合のみで、これは端末側の任意設定でアプリからは検知・変更不可)。

[[free-apple-id-device-signing]]で実機に入れて確認する運用と合わせて使う。ライフサポート部で通知・アラーム系の
機能を作る時にも当てはまる知見。
