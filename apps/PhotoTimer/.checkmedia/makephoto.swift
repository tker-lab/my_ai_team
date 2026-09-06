import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let width = Int(CommandLine.arguments[2])!
let height = Int(CommandLine.arguments[3])!
let hue = CGFloat(Double(CommandLine.arguments[4])!)

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
NSColor(hue: hue, saturation: 0.7, brightness: 0.85, alpha: 1.0).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
NSColor(hue: (hue + 0.5).truncatingRemainder(dividingBy: 1.0), saturation: 0.9, brightness: 0.95, alpha: 1.0).setFill()
NSRect(x: width/4, y: height/4, width: width/2, height: height/2).fill()
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let data = rep.representation(using: .jpeg, properties: [:])!
try! data.write(to: outputURL)
print("done")
