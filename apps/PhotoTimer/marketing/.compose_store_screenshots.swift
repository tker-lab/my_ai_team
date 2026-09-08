import AppKit
import CoreGraphics
import ImageIO
import Foundation

let root = "/Users/takahashitakayuki/my_ai_team/apps/PhotoTimer"
let outDir = root + "/marketing/app-store-screenshots"
let verifyDir = root + "/verify"
let W: CGFloat = 1242
let H: CGFloat = 2688

func image(_ path: String) -> CGImage {
    let url = URL(fileURLWithPath: path)
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(source, 0, nil)!
}

func crop(_ source: CGImage, _ rect: CGRect) -> CGImage {
    source.cropping(to: rect)!
}

func drawAspectFill(_ ctx: CGContext, _ source: CGImage, _ dest: CGRect) {
    let sx = dest.width / CGFloat(source.width)
    let sy = dest.height / CGFloat(source.height)
    let scale = max(sx, sy)
    let w = CGFloat(source.width) * scale
    let h = CGFloat(source.height) * scale
    let r = CGRect(x: dest.midX - w / 2, y: dest.midY - h / 2, width: w, height: h)
    ctx.saveGState()
    ctx.addRect(dest)
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(source, in: r)
    ctx.restoreGState()
}

func drawFit(_ ctx: CGContext, _ source: CGImage, _ dest: CGRect) {
    ctx.saveGState()
    ctx.interpolationQuality = .high
    ctx.draw(source, in: dest)
    ctx.restoreGState()
}

func keyBlack(_ source: CGImage, _ rect: CGRect) -> CGImage {
    let cropped = source.cropping(to: rect)!
    let w = cropped.width, h = cropped.height
    let bpr = w * 4
    var pixels = [UInt8](repeating: 0, count: bpr * h)
    let c = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let lum = (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
        let a = UInt8(max(0, min(255, (220 - lum) * 2)))
        pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = a
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

func drawBase(_ base: CGImage, overlays: [(CGImage, CGRect)]) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(base, in: CGRect(x: 0, y: 0, width: W, height: H))
    let sx = W / CGFloat(base.width)
    let sy = H / CGFloat(base.height)
    for (im, r) in overlays {
        // Callers specify the rectangle in the screenshot's top-left coordinate system.
        let bottomY = CGFloat(base.height) - r.minY - r.height
        drawAspectFill(ctx, im, CGRect(x: r.minX * sx, y: bottomY * sy, width: r.width * sx, height: r.height * sy))
    }
    return ctx.makeImage()!
}

func save(_ im: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: outDir + "/" + name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, im, nil)
    CGImageDestinationFinalize(dest)
}

// Use the last committed marketing images as photo sources, never the files being overwritten.
let peopleWhole = image("/private/tmp/phototimer_original_02.png")
let dogWhole = image("/private/tmp/phototimer_original_04.png")
let childrenWhole = image("/private/tmp/phototimer_original_05.png")
let people = crop(peopleWhole, CGRect(x: 60, y: 180, width: 1080, height: 820))
let dog = crop(dogWhole, CGRect(x: 370, y: 180, width: 540, height: 820))
let baby = crop(childrenWhole, CGRect(x: 50, y: 450, width: 1100, height: 610))
let play = crop(childrenWhole, CGRect(x: 50, y: 1065, width: 1100, height: 600))
let sports = crop(childrenWhole, CGRect(x: 50, y: 1670, width: 1100, height: 610))

// 01: the actual blue home screen from verification, with the current app name.
let homeBase = image(verifyDir + "/v10_theme_01_home_default_theme.png")
let home = drawBase(homeBase, overlays: [])
let homeCtx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
homeCtx.draw(home, in: CGRect(x: 0, y: 0, width: W, height: H))
// Mask only the old title, then draw the current product name in the same UI position.
homeCtx.setFillColor(CGColor(red: 0.90, green: 0.94, blue: 1.0, alpha: 1))
homeCtx.fill(CGRect(x: 48, y: H - 490, width: 720, height: 130))
let oldHome = image("/private/tmp/phototimer_original_01.png")
let title = keyBlack(oldHome, CGRect(x: 220, y: 320, width: 820, height: 220))
drawFit(homeCtx, title, CGRect(x: 48, y: H - 490, width: 720, height: 130))
save(homeCtx.makeImage()!, "01_home.png")

// 02: actual retirement/wedding-style running frame, with only its media area replaced.
let peopleBase = image(verifyDir + "/v10_patterns_01_結婚式ムービー風_running_t0.png")
save(drawBase(peopleBase, overlays: [(people, CGRect(x: 4, y: 865, width: 1198, height: 900))]), "02_people.png")

// 03: actual end-of-timer single-delete confirmation UI; replace the displayed photo only.
let deleteBase = image(verifyDir + "/v7_deleteconfirm_02_selection_confirmation.png")
save(drawBase(deleteBase, overlays: [
    (people, CGRect(x: 96, y: 810, width: 330, height: 270)),
    (dog, CGRect(x: 438, y: 810, width: 330, height: 270)),
    (baby, CGRect(x: 780, y: 810, width: 330, height: 270))
]), "03_delete_and_organize.png")

// 04: actual retirement-style running frame, with the full dog kept inside its media window.
let dogBase = image(verifyDir + "/v10_patterns_09_引退セレモニー風_running_t0.png")
save(drawBase(dogBase, overlays: [(dog, CGRect(x: 4, y: 910, width: 1198, height: 800))]), "04_dog.png")

// 05: actual NG/end-roll frame. The pattern's three media beats remain in one screen.
let ngBase = image(verifyDir + "/v10_patterns_13_NG集エンドロール風_running_t0.png")
save(drawBase(ngBase, overlays: [
    (baby, CGRect(x: 338, y: 392, width: 528, height: 790)),
    (play, CGRect(x: 0, y: 1580, width: 600, height: 710)),
    (sports, CGRect(x: 602, y: 1580, width: 600, height: 710))
]), "05_children_premium.png")

print("composed 5 screenshots")
