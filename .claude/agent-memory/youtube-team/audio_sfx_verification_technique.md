---
name: audio-sfx-verification-technique
description: 編集済み動画に特定の効果音(ベル・BGM等)が実際に入っているかを、聴かずに機械的に確認する方法
metadata:
  type: reference
---

動画ファイルを目視(フレーム確認)だけでなく、効果音の有無を確認したい場合の手順。Claude自身は音声を聴けないため、正規化相互相関(normalized cross-correlation)で機械的に照合する。

**手順**
1. `ffmpeg`で対象の効果音素材(例:cutin_bell.mp3)と、動画側の該当区間の音声を、同じサンプルレート・モノラルのWAVに変換して書き出す(`-ac 1 -ar 8000 -f wav`で十分。8kHzまで落とすとnumpy処理が軽くなる)
2. 動画側は疑わしい区間の前後数秒を含めて広めに切り出す(例:カットインの視覚的な切り替わり検出時刻の前後3秒など)
3. Python(numpy)で `np.correlate(動画側, 素材側, mode='valid')` を各区間のエネルギーで正規化(NCC)し、ピーク値を見る。目安として **NCC 0.7以上なら実質一致**、0.1以下ならほぼ無関係と判断してよい(cutin_bell.mp3で0.84〜0.91、ending_bgm.mp3で0.70の実績あり)
4. BGMのように尺が長い素材は、動画側の短い区間を「型」にして素材全体をスライドさせて探す(逆方向の相関)。素材の先頭からではなく途中から使われているケースがあるため、素材の先頭数十秒だけを比較すると「使われていない」と誤判定することがある(実際に ending_bgm.mp3 は27秒地点から使われていた)
5. numpyが環境に無い場合は `pip3 install --break-system-packages numpy` で導入可(Homebrew管理のPython環境だとPEP668で素の`pip install`は拒否されるため)

**視覚側の切り替わり検出**には `ffmpeg -filter:v "select='gt(scene,0.35)',showinfo"` でシーンチェンジのタイムスタンプを一括取得できる。カットイン画像への切り替わり候補を先にこれで絞り込んでから、その前後で音声照合すると効率的。

関連: [[video1_v5_status]] の効果音確認で実際に使用した手順。
