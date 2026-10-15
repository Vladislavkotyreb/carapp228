// Код SF Symbol в шрифте SF Pro по имени символа — для макетов в Figma,
// где значок ставится текстом SF Pro с этим кодом.
//
// Прямо по имени не найти: глифы в SFSymbolsFallback.otf названы uniXXXXXX,
// а порядок в name_availability/symbol_order с кодами не совпадает. Поэтому
// сравнение формы: символ рисуется AppKit, каждый глиф шрифта — CoreText,
// оба приводятся к рамке по краске и сэмплу 20×20. Сравнивать с Semibold-
// начертанием: в Ultralight тонкие линии теряются при сжатии.
//
//   swiftc -O tools/sf-symbol-codepoint.swift -o /tmp/sfcp
//   /tmp/sfcp drop.fill line.3.horizontal.decrease
//
// Печатает пять кандидатов на имя и кладёт contact.png (слева символ, справа
// кандидаты) — первый не всегда верный, смотреть глазами. Нужен установленный
// SF Symbols.app. В приложение не входит.

import AppKit
import CoreText

let N = 20
func normalize(_ img: CGImage) -> [Float]? {
    // bbox of ink by alpha, then resample to N×N
    let w = img.width, h = img.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var minx = w, miny = h, maxx = -1, maxy = -1
    for y in 0..<h { for x in 0..<w where p[y*w+x] > 60 { minx = min(minx,x); maxx = max(maxx,x); miny = min(miny,y); maxy = max(maxy,y) } }
    if maxx < 0 { return nil }
    let bw = maxx-minx+1, bh = maxy-miny+1
    var out = [Float](repeating: 0, count: N*N+1)
    for j in 0..<N { for i in 0..<N {
        var s: Float = 0; var c: Float = 0
        let x0 = minx + i*bw/N, x1 = max(x0+1, minx + (i+1)*bw/N)
        let y0 = miny + j*bh/N, y1 = max(y0+1, miny + (j+1)*bh/N)
        for y in y0..<y1 { for x in x0..<x1 { s += Float(p[y*w+x]); c += 1 } }
        out[j*N+i] = s/c/255
    } }
    out[N*N] = Float(bw)/Float(bh)
    return out
}
func render(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 96,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
    draw(ctx); return ctx.makeImage()!
}
let names = Array(CommandLine.arguments.dropFirst())
var targets: [(String, [Float])] = []
for n in names {
    guard let sym = NSImage(systemSymbolName: n, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 48, weight: .semibold)) else { print(n, "no symbol"); continue }
    var r = CGRect(x: 0, y: 0, width: 96, height: 96)
    let cgi = sym.cgImage(forProposedRect: &r, context: nil, hints: nil)!
    let img = render { $0.draw(cgi, in: CGRect(x: 8, y: 8, width: 80, height: 80 * CGFloat(cgi.height)/CGFloat(cgi.width))) }
    if let v = normalize(img) { targets.append((n, v)) }
}
let url = URL(fileURLWithPath: "/Applications/SF Symbols.app/Contents/Resources/Fonts/SFSymbolsFallback.otf")
let all = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as! [CTFontDescriptor]
let desc = all.first { (CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String ?? "").contains("Semibold") } ?? all[0]
print("faces:", all.count, CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String ?? "")
let font = CTFontCreateWithFontDescriptor(desc, 48, nil)
var best = [String: [(Float, Int)]]()
for cp in 0x100000...0x10FFFD {
    var u = Array(String(UnicodeScalar(cp)!).utf16); var g = [CGGlyph](repeating: 0, count: u.count)
    guard CTFontGetGlyphsForCharacters(font, &u, &g, u.count), g[0] != 0 else { continue }
    guard let path = CTFontCreatePathForGlyph(font, g[0], nil) else { continue }
    let img = render { ctx in ctx.translateBy(x: 20, y: 30); ctx.addPath(path); ctx.setFillColor(gray: 1, alpha: 1); ctx.fillPath() }
    guard let v = normalize(img) else { continue }
    for (n, t) in targets {
        var d: Float = 0
        for k in 0..<(N*N) { let e = v[k]-t[k]; d += e*e }
        d += 40 * abs(v[N*N]-t[N*N])
        var arr = best[n] ?? []; arr.append((d, cp)); arr.sort { $0.0 < $1.0 }; if arr.count > 5 { arr.removeLast() }; best[n] = arr
    }
}
// contact sheet: row per name: symbol, then 5 candidates
let W = 64, rows = names.count
let sheet = CGContext(data: nil, width: W*6, height: W*rows, bitsPerComponent: 8, bytesPerRow: W*6*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1)); sheet.fill(CGRect(x:0,y:0,width:W*6,height:W*rows))
let small = CTFontCreateWithFontDescriptor(desc, 36, nil)
for (r, n) in names.enumerated() {
    let y = CGFloat((rows-1-r)*W)
    if let sym = NSImage(systemSymbolName: n, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 32, weight: .medium)) {
        var rr = CGRect(x:0,y:0,width:48,height:48); let ci = sym.cgImage(forProposedRect: &rr, context: nil, hints: nil)!
        sheet.draw(ci, in: CGRect(x: 8, y: y+8, width: 48, height: 48*CGFloat(ci.height)/CGFloat(ci.width)))
    }
    let cands = best[n] ?? []
    print(n, cands.map { String(format: "%X", $0.1) }.joined(separator: " "))
    for (k, c) in cands.enumerated() {
        var u = Array(String(UnicodeScalar(c.1)!).utf16); var g = [CGGlyph](repeating: 0, count: u.count)
        _ = CTFontGetGlyphsForCharacters(small, &u, &g, u.count)
        if let p = CTFontCreatePathForGlyph(small, g[0], nil) {
            sheet.saveGState(); sheet.translateBy(x: CGFloat((k+1)*W)+10, y: y+18); sheet.addPath(p); sheet.setFillColor(CGColor(red:0,green:0,blue:0,alpha:1)); sheet.fillPath(); sheet.restoreGState()
        }
    }
}
let out = sheet.makeImage()!
let rep = NSBitmapImageRep(cgImage: out); try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "contact.png"))
