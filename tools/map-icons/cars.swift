// Compile after the shared lighting/material helpers from render.swift (before its Render section).
// Orthographic top-view miniatures, nose up. Stylized catalog profiles, not CAD replicas.
struct CarProfile: Decodable { let slug: String; let body: String; let length: CGFloat; let width: CGFloat }
let profiles = try JSONDecoder().decode([CarProfile].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
let selected = CommandLine.arguments.count > 4 ? Set(CommandLine.arguments[4].split(separator: ",").map(String.init)) : Set(profiles.map(\.slug))

func carMarker(_ p: CarProfile) -> SCNNode {
    let root = SCNNode()
    let half: CGFloat = 1.8, w = 3.6 * p.width / p.length / 2
    let boxy = p.body == "box"
    let longRoof = ["suv", "box", "wagon", "hatch"].contains(p.body)
    let coupe = ["coupe", "coupeSUV", "roadster"].contains(p.body)
    let classic = p.slug.hasPrefix("lada-21") || p.slug == "uaz-hunter"
    let paint = pbr(p.slug == "giraffe-discovery" ? rgb(250, 205, 123) : rgb(235, 239, 243), metal: 0.35, rough: 0.25)
    let glass = pbr(rgb(50, 66, 79), metal: 0.65, rough: 0.20)
    let dark = pbr(rgb(24, 26, 29), metal: 0, rough: 0.60)
    let chrome = pbr(rgb(175, 185, 195), metal: 0.9, rough: 0.28)
    func slab(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ length: CGFloat, _ depth: CGFloat, _ z: CGFloat, _ material: SCNMaterial, _ radius: CGFloat = 0.04) {
        let g = SCNBox(width: width, height: length, length: depth, chamferRadius: radius)
        g.materials = [material]
        let n = SCNNode(geometry: g); n.position = SCNVector3(x, y, z); root.addChildNode(n)
    }
    func surface(_ path: NSBezierPath, _ z: CGFloat, _ depth: CGFloat, _ material: SCNMaterial, _ bevel: CGFloat) {
        let g = SCNShape(path: path, extrusionDepth: depth); g.chamferRadius = bevel; g.materials = [material]
        let n = SCNNode(geometry: g); n.position.z = z; root.addChildNode(n)
    }
    // Wheelbase and roof geometry are shared by body families; footprint uses each model's proportions.
    for x in [-w, w] { for y: CGFloat in [-1.12, 1.10] { slab(x, y, 0.17, 0.47, 0.16, 0, dark, 0.06) } }
    let outline = NSBezierPath()
    let nose: CGFloat = boxy ? 0.90 : 0.79
    outline.move(to: NSPoint(x: -w * nose, y: half))
    outline.curve(to: NSPoint(x: w * nose, y: half), controlPoint1: NSPoint(x: -w * 0.35, y: half + (boxy ? 0 : 0.04)), controlPoint2: NSPoint(x: w * 0.35, y: half + (boxy ? 0 : 0.04)))
    outline.curve(to: NSPoint(x: w, y: 1.3), controlPoint1: NSPoint(x: w, y: half), controlPoint2: NSPoint(x: w, y: 1.5))
    outline.line(to: NSPoint(x: w, y: -1.25))
    outline.curve(to: NSPoint(x: w * 0.86, y: -half), controlPoint1: NSPoint(x: w, y: -1.6), controlPoint2: NSPoint(x: w, y: -half))
    outline.line(to: NSPoint(x: -w * 0.86, y: -half))
    outline.curve(to: NSPoint(x: -w, y: -1.25), controlPoint1: NSPoint(x: -w, y: -half), controlPoint2: NSPoint(x: -w, y: -1.6))
    outline.line(to: NSPoint(x: -w, y: 1.3))
    outline.curve(to: NSPoint(x: -w * nose, y: half), controlPoint1: NSPoint(x: -w, y: 1.5), controlPoint2: NSPoint(x: -w, y: half)); outline.close()
    surface(outline, 0.08, 0.24, paint, boxy ? 0.05 : 0.10)
    // Cabin perimeter / side glazing, with painted roof and visible front/rear windscreens.
    let front: CGFloat = p.body == "roadster" ? 0.25 : (longRoof ? 0.78 : 0.60)
    let rear: CGFloat = longRoof ? -1.35 : (coupe ? -0.92 : -1.02)
    let cabin = NSBezierPath()
    cabin.move(to: NSPoint(x: -w * 0.77, y: front))
    cabin.curve(to: NSPoint(x: w * 0.77, y: front), controlPoint1: NSPoint(x: -w * 0.35, y: front + 0.12), controlPoint2: NSPoint(x: w * 0.35, y: front + 0.12))
    cabin.line(to: NSPoint(x: w * (boxy ? 0.76 : 0.66), y: rear)); cabin.line(to: NSPoint(x: -w * (boxy ? 0.76 : 0.66), y: rear)); cabin.close()
    surface(cabin, 0.25, 0.10, chrome, 0.025)
    let inset = cabin.copy() as! NSBezierPath; let transform = AffineTransform(scaleByX: 0.965, byY: 0.975); inset.transform(using: transform)
    surface(inset, 0.31, 0.08, glass, 0.025)
    let roofFront = front - (classic ? 0.24 : 0.40), roofRear = rear + (longRoof ? 0.20 : 0.36)
    let roof = NSBezierPath()
    let rf = w * (boxy ? 0.69 : 0.62), rr = w * (boxy ? 0.69 : 0.56)
    roof.move(to: NSPoint(x: -rf + 0.08, y: roofFront))
    roof.line(to: NSPoint(x: rf - 0.08, y: roofFront))
    roof.curve(to: NSPoint(x: rf, y: roofFront - 0.08), controlPoint1: NSPoint(x: rf, y: roofFront), controlPoint2: NSPoint(x: rf, y: roofFront))
    roof.line(to: NSPoint(x: rr, y: roofRear + 0.08))
    roof.curve(to: NSPoint(x: rr - 0.08, y: roofRear), controlPoint1: NSPoint(x: rr, y: roofRear), controlPoint2: NSPoint(x: rr, y: roofRear))
    roof.line(to: NSPoint(x: -rr + 0.08, y: roofRear))
    roof.curve(to: NSPoint(x: -rr, y: roofRear + 0.08), controlPoint1: NSPoint(x: -rr, y: roofRear), controlPoint2: NSPoint(x: -rr, y: roofRear))
    roof.line(to: NSPoint(x: -rf, y: roofFront - 0.08))
    roof.curve(to: NSPoint(x: -rf + 0.08, y: roofFront), controlPoint1: NSPoint(x: -rf, y: roofFront), controlPoint2: NSPoint(x: -rf, y: roofFront)); roof.close()
    surface(roof, 0.40, 0.12, paint, 0.045)
    // Painted pillars separate side windows rather than one unbroken dark rectangle.
    for x in [-1.0, 1.0] as [CGFloat] {
        slab(x * w * 0.70, (roofFront + roofRear) / 2, 0.11, 0.07, 0.05, 0.38, paint, 0.015)
    }
    // Sunroof is intentionally omitted on the older/basic catalog cars.
    if !classic && (p.slug.hasPrefix("bmw") || p.slug.hasPrefix("mercedes") || p.slug.hasPrefix("geely") || p.slug == "giraffe-discovery") {
        slab(0, (roofFront + roofRear) / 2, w * 1.02, (roofFront - roofRear) * 0.67, 0.02, 0.50, glass, 0.04)
    }
    for x in [-1.0, 1.0] as [CGFloat] {
        slab(x * (w + 0.045), front - 0.03, 0.24, 0.16, 0.12, 0.20, paint, 0.06)
        slab(x * w * 0.63, 1.59, w * 0.49, classic ? 0.16 : 0.13, 0.04, 0.24,
             pbr(rgb(205, 230, 250), metal: 0.4, rough: 0.18), 0.035)
        slab(x * w * 0.70, -1.63, w * 0.34, 0.12, 0.035, 0.24,
             pbr(rgb(225, 48, 42), metal: 0.2, rough: 0.25), 0.03)
        // Hood crease / roof rails are fine details readable at 3x.
        slab(x * w * 0.47, (front + 1.40) / 2, 0.012, 1.35 - front, 0.012, 0.22, chrome, 0.004)
        if longRoof && !classic { slab(x * w * 0.72, (roofFront + roofRear) / 2, 0.035, roofFront - roofRear, 0.035, 0.47, chrome, 0.012) }
    }
    if p.slug == "giraffe-discovery" {
        let spot = pbr(rgb(170, 79, 20), metal: 0.15, rough: 0.38)
        for (x,y,s) in [(-0.28,1.13,0.27),(0.28,1.35,0.24),(0.0,0.9,0.19),(-0.34,-1.53,0.17),(0.28,-1.55,0.22)] as [(CGFloat,CGFloat,CGFloat)] {
            let path = NSBezierPath(roundedRect: NSRect(x:x-s/2,y:y-s/2,width:s,height:s*0.85),xRadius:0.07,yRadius:0.09)
            surface(path,0.225,0.01,spot,0.002)
        }
    }
    return root
}

let markerDevice = MTLCreateSystemDefaultDevice()!
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for profile in profiles where selected.contains(profile.slug) {
    let scene = SCNScene(); scene.background.contents = NSColor.clear
    scene.lightingEnvironment.contents = sky(); scene.lightingEnvironment.intensity = 0.65
    scene.rootNode.addChildNode(carMarker(profile))
    let light = SCNNode(); light.light = SCNLight(); light.light!.type = .directional; light.light!.intensity = 650
    light.eulerAngles = SCNVector3(-0.45,-0.50,0); scene.rootNode.addChildNode(light)
    let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .ambient; fill.light!.intensity = 120; scene.rootNode.addChildNode(fill)
    let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera!.usesOrthographicProjection = true
    camera.camera!.orthographicScale = 2.25; camera.camera!.wantsHDR = true; camera.camera!.wantsExposureAdaptation = false; camera.camera!.exposureOffset = -0.15
    camera.position = SCNVector3(0,0,12); scene.rootNode.addChildNode(camera)
    let renderer = SCNRenderer(device: markerDevice, options: nil); renderer.scene = scene; renderer.pointOfView = camera
    let image = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .multisampling4X)
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath:"\(out)/\(profile.slug).png"))
    print(profile.slug)
}
