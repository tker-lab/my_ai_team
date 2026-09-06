import AVFoundation
import CoreGraphics
import CoreImage
import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: outputURL)
let writer = try! AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let width = 640, height = 480
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let fps: Int32 = 10
let totalFrames = 60 // 6 seconds
var frameCount = 0
let queue = DispatchQueue(label: "vid")
let semaphore = DispatchSemaphore(value: 0)

input.requestMediaDataWhenReady(on: queue) {
    while input.isReadyForMoreMediaData && frameCount < totalFrames {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
        guard let buffer = pixelBuffer else { continue }
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        let hue = CGFloat(frameCount) / CGFloat(totalFrames)
        let color = NSColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1.0)
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let time = CMTime(value: Int64(frameCount), timescale: fps)
        adaptor.append(buffer, withPresentationTime: time)
        frameCount += 1
    }
    if frameCount >= totalFrames {
        input.markAsFinished()
        writer.finishWriting {
            semaphore.signal()
        }
    }
}
semaphore.wait()
print("done")
