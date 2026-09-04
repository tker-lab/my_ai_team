import Foundation

/// マナースイッチ(消音スイッチ)がオンでも聞こえるアラーム音を鳴らすためのデータを作る。
///
/// 【なぜ音声ファイルを同梱せず、その場で音を生成しているか】
/// `AudioServicesPlaySystemSound`(短い操作音向けのAPI)は消音スイッチを一切無視できないことが分かり、
/// `AVAudioPlayer` で実際の音声データを(.playback カテゴリのセッションの下で)再生する方式に変更した
/// (詳細は TimerController.finish() のコメント参照)。AVAudioPlayer は「音声ファイル」か「音声データ」を
/// 必要とするが、このアプリは「外部から素材を取得しない・サーバーを持たない」という設計方針のため、
/// 短いビープ音をコード側でその場で作り、WAV形式のデータとして渡す(端末内で完結し、追加のアプリ内
/// 素材ファイルも不要)。
enum AlarmTone {

    /// 「ピッ、ピッ、ピッ」と短いビープ音を3回鳴らすWAVデータ(合計 約1.05秒)。
    /// 一度だけ計算し、以後は使い回す(タイマー終了のたびに再計算する必要はないため)。
    static let data: Data = makeAlarmWAVData()

    private static func makeAlarmWAVData() -> Data {
        let sampleRate = 44_100.0
        let frequency = 880.0 // 音の高さ(Hz)。目覚まし時計のビープ音に近い高さを選んだ
        let beepDuration = 0.15
        let silenceDuration = 0.1
        let beepCount = 3
        let amplitude = 12_000.0 // Int16の最大値(32767)に対して十分な音量かつクリップしない値
        let fadeDuration = 0.008 // 開始・終了を滑らかにし、「プツッ」というノイズ音を防ぐ

        var samples: [Int16] = []
        let beepSampleCount = Int(sampleRate * beepDuration)
        let fadeSampleCount = max(1, Int(sampleRate * fadeDuration))
        let silenceSampleCount = Int(sampleRate * silenceDuration)

        for _ in 0..<beepCount {
            for n in 0..<beepSampleCount {
                let t = Double(n) / sampleRate
                var gain = 1.0
                if n < fadeSampleCount {
                    gain = Double(n) / Double(fadeSampleCount)
                } else if n > beepSampleCount - fadeSampleCount {
                    gain = Double(beepSampleCount - n) / Double(fadeSampleCount)
                }
                let value = sin(2.0 * Double.pi * frequency * t) * gain * amplitude
                samples.append(Int16(clamping: Int(value)))
            }
            samples.append(contentsOf: [Int16](repeating: 0, count: silenceSampleCount))
        }

        return wavData(from: samples, sampleRate: Int(sampleRate))
    }

    /// 16bit・モノラルのPCMサンプル列を、そのままAVAudioPlayerに渡せるWAV形式のDataに変換する。
    private static func wavData(from samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
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
        appendUInt32LE(UInt32(sampleRate))
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
