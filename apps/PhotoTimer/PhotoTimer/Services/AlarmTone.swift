import Foundation

/// タイマー終了時に鳴らす音色の選択肢。CEO要望(2026-09-05)
/// 「このピピピだと気づかない。音色も何パターンか選べるように」への対応。
enum AlarmTonePattern: String, Codable, CaseIterable, Identifiable, Equatable {
    case beep = "ピピピ"
    case bell = "ベル"
    case siren = "サイレン"

    var id: String { rawValue }
}

/// マナースイッチ(消音スイッチ)がオンでも聞こえるアラーム音を鳴らすためのデータを作る。
///
/// 【なぜ音声ファイルを同梱せず、その場で音を生成しているか】
/// `AudioServicesPlaySystemSound`(短い操作音向けのAPI)は消音スイッチを一切無視できないことが分かり、
/// `AVAudioPlayer` で実際の音声データを(.playback カテゴリのセッションの下で)再生する方式に変更した
/// (詳細は TimerController.swift のコメント参照)。AVAudioPlayer は「音声ファイル」か「音声データ」を
/// 必要とするが、このアプリは「外部から素材を取得しない・サーバーを持たない」という設計方針のため、
/// 短い音をコード側でその場で作り、WAV形式のデータとして渡す(端末内で完結し、追加のアプリ内
/// 素材ファイルも不要)。
///
/// 【2026-09-05変更】音色ごとに「1サイクル分」のデータを作り、TimerController側で
/// AVAudioPlayer.numberOfLoops を使ってこれを繰り返す設計にした。「n回鳴って終わる」も
/// 「止めるまで鳴り続ける」も、どちらもこの1サイクル分を繰り返す回数を変えているだけ
/// (iPhone標準の「時計」アプリが短いジングルをループ再生するのと同じ考え方)。
/// あわせて「気づきにくい」というCEOの声を受け、以前より音量(振幅)を上げ、単純なビープに
/// 加えて「ベル」「サイレン」の2種類を追加した。
enum AlarmTone {

    static func data(for pattern: AlarmTonePattern) -> Data {
        switch pattern {
        case .beep: return beepData
        case .bell: return bellData
        case .siren: return sirenData
        }
    }

    private static let sampleRate = 44_100.0
    /// Int16の最大値(32767)に対して十分な音量かつクリップしない値。以前(12,000)から引き上げ、
    /// 「気づきやすさ」を優先した(CEOの実機報告「ピピピだと気づかない」への対応)。
    private static let amplitude = 27_000.0

    /// 「ピッ、ピッ、ピッ」。以前より高い音程・大きい音量にして気づきやすくした。
    private static let beepData: Data = {
        var samples: [Int16] = []
        for _ in 0..<3 {
            samples += tone(frequency: 1046.5, duration: 0.15) // C6に近い高さ。以前の880Hzより高く鋭い
            samples += silence(duration: 0.1)
        }
        samples += silence(duration: 0.25) // 1サイクルの末尾の間(ループ時に詰まって聞こえないように)
        return wavData(from: samples)
    }()

    /// 「ピンポン、ピンポン」と高低2音を交互に鳴らす、ベル・チャイム風の音。
    private static let bellData: Data = {
        var samples: [Int16] = []
        for _ in 0..<2 {
            samples += tone(frequency: 1318.5, duration: 0.18) // 高い「ピン」
            samples += silence(duration: 0.03)
            samples += tone(frequency: 987.8, duration: 0.24) // 低い「ポン」
            samples += silence(duration: 0.15)
        }
        samples += silence(duration: 0.2)
        return wavData(from: samples)
    }()

    /// 音の高さが上下にうねる「ウーウー」というサイレン風の音。緊急性を感じやすく、
    /// 単調なビープよりも聞き逃しにくいと考え追加した。
    private static let sirenData: Data = {
        var samples: [Int16] = []
        samples += sweep(from: 700, to: 1500, duration: 0.4)
        samples += sweep(from: 1500, to: 700, duration: 0.4)
        samples += silence(duration: 0.15)
        return wavData(from: samples)
    }()

    // MARK: - 音の合成

    private static func tone(frequency: Double, duration: Double, fadeDuration: Double = 0.008) -> [Int16] {
        let sampleCount = Int(sampleRate * duration)
        let fadeSampleCount = max(1, Int(sampleRate * fadeDuration))
        var samples: [Int16] = []
        samples.reserveCapacity(sampleCount)
        for n in 0..<sampleCount {
            let t = Double(n) / sampleRate
            let gain = fadeGain(n: n, sampleCount: sampleCount, fadeSampleCount: fadeSampleCount)
            let value = sin(2.0 * Double.pi * frequency * t) * gain * amplitude
            samples.append(Int16(clamping: Int(value)))
        }
        return samples
    }

    /// 開始と終了の周波数を滑らかにつなぐ「うねり」音(チャープ)。瞬間ごとの周波数を積分して
    /// 位相を進める方式にすることで、途中で音がプツッと途切れたりズレたりしないようにしている。
    private static func sweep(from startFrequency: Double, to endFrequency: Double, duration: Double, fadeDuration: Double = 0.01) -> [Int16] {
        let sampleCount = Int(sampleRate * duration)
        let fadeSampleCount = max(1, Int(sampleRate * fadeDuration))
        var samples: [Int16] = []
        samples.reserveCapacity(sampleCount)
        var phase = 0.0
        for n in 0..<sampleCount {
            let progress = Double(n) / Double(sampleCount)
            let frequency = startFrequency + (endFrequency - startFrequency) * progress
            phase += 2.0 * Double.pi * frequency / sampleRate
            let gain = fadeGain(n: n, sampleCount: sampleCount, fadeSampleCount: fadeSampleCount)
            let value = sin(phase) * gain * amplitude
            samples.append(Int16(clamping: Int(value)))
        }
        return samples
    }

    /// 開始・終了を滑らかにし、「プツッ」というノイズ音を防ぐためのフェード係数(0〜1)。
    private static func fadeGain(n: Int, sampleCount: Int, fadeSampleCount: Int) -> Double {
        if n < fadeSampleCount {
            return Double(n) / Double(fadeSampleCount)
        } else if n > sampleCount - fadeSampleCount {
            return Double(sampleCount - n) / Double(fadeSampleCount)
        }
        return 1.0
    }

    private static func silence(duration: Double) -> [Int16] {
        [Int16](repeating: 0, count: Int(sampleRate * duration))
    }

    /// 16bit・モノラルのPCMサンプル列を、そのままAVAudioPlayerに渡せるWAV形式のDataに変換する。
    private static func wavData(from samples: [Int16]) -> Data {
        var data = Data()
        let channels = 1
        let bitsPerSample = 16
        let sr = Int(sampleRate)
        let byteRate = sr * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * 2

        func appendASCII(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func appendUInt32LE(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func appendUInt16LE(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }

        appendASCII("RIFF")
        appendUInt32LE(UInt32(36 + dataSize))
        appendASCII("WAVE")

        appendASCII("fmt ")
        appendUInt32LE(16) // fmtチャンクのサイズ
        appendUInt16LE(1) // フォーマット=1(PCM、圧縮なし)
        appendUInt16LE(UInt16(channels))
        appendUInt32LE(UInt32(sr))
        appendUInt32LE(UInt32(byteRate))
        appendUInt16LE(UInt16(blockAlign))
        appendUInt16LE(UInt16(bitsPerSample))

        appendASCII("data")
        appendUInt32LE(UInt32(dataSize))
        for sample in samples {
            appendUInt16LE(UInt16(bitPattern: sample))
        }

        return data
    }
}
