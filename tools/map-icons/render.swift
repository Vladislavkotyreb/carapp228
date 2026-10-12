// Объёмные метки карты: шина (шиномонтаж), ключ с отвёрткой (СТО), звезда
// (избранное). Собираются из примитивов SceneKit и рендерятся в PNG с
// прозрачным фоном под углом три четверти сверху.
//
//   swiftc -O render.swift -o /tmp/map-icons && /tmp/map-icons <папка> [размер]
import AppKit
import SceneKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let side = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 384

func pbr(_ color: NSColor, metal: CGFloat, rough: CGFloat) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = color
    m.metalness.contents = metal
    m.roughness.contents = rough
    return m
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

/// Небо для отражений: светлый верх, тёплый горизонт, тёмный низ.
func sky() -> NSImage {
    let size = NSSize(width: 512, height: 256)
    let image = NSImage(size: size)
    image.lockFocus()
    NSGradient(colorsAndLocations: (rgb(40, 42, 48), 0), (rgb(150, 150, 155), 0.45),
               (rgb(255, 250, 240), 0.62), (rgb(210, 225, 255), 1))!
        .draw(in: NSRect(origin: .zero, size: size), angle: 90)
    // Софтбокс — яркое пятно сверху сбоку, оно и даёт блик.
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 300, y: 170, width: 120, height: 60)).fill()
    image.unlockFocus()
    return image
}

func shadowBlob() -> NSImage {
    let size = NSSize(width: 256, height: 256)
    let image = NSImage(size: size)
    image.lockFocus()
    NSGradient(colorsAndLocations: (NSColor(white: 0, alpha: 0.40), 0), (NSColor(white: 0, alpha: 0.16), 0.32),
               (NSColor(white: 0, alpha: 0), 0.66), (NSColor(white: 0, alpha: 0), 1))!
        .draw(in: NSRect(origin: .zero, size: size), relativeCenterPosition: .zero)
    image.unlockFocus()
    return image
}

func makeScene(_ model: SCNNode, yaw: CGFloat, pitch: CGFloat, distance: CGFloat,
               shadow: Bool = true) -> SCNScene {
    let scene = SCNScene()
    scene.lightingEnvironment.contents = sky()
    scene.lightingEnvironment.intensity = 1.3
    scene.rootNode.addChildNode(model)

    // Пятно тени под моделью: метка лежит на карте, а не висит.
    let (minBox, maxBox) = model.boundingBox
    let low = model.convertPosition(minBox, to: nil), high = model.convertPosition(maxBox, to: nil)
    let spread = max(CGFloat(high.x - low.x), CGFloat(high.z - low.z)) * 1.25
    let floor = SCNNode(geometry: SCNPlane(width: spread, height: spread * 0.8))
    floor.eulerAngles.x = -.pi / 2
    floor.position = SCNVector3(0.12, CGFloat(low.y) - 0.02, 0.1)
    let blob = SCNMaterial()
    blob.lightingModel = .constant
    blob.diffuse.contents = shadowBlob()
    blob.writesToDepthBuffer = false
    floor.geometry!.materials = [blob]
    floor.renderingOrder = -1
    if shadow { scene.rootNode.addChildNode(floor) }

    let key = SCNNode()
    key.light = SCNLight()
    key.light!.type = .directional
    key.light!.intensity = 850
    key.eulerAngles = SCNVector3(-1.05, 0.5, 0)
    scene.rootNode.addChildNode(key)
    let fill = SCNNode()
    fill.light = SCNLight()
    fill.light!.type = .directional
    fill.light!.intensity = 250
    fill.eulerAngles = SCNVector3(-0.3, -1.1, 0)
    scene.rootNode.addChildNode(fill)

    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera!.fieldOfView = 22
    camera.camera!.wantsHDR = true
    camera.camera!.wantsExposureAdaptation = false
    let pivot = SCNNode()
    pivot.addChildNode(camera)
    camera.position = SCNVector3(0, 0, distance)
    pivot.eulerAngles = SCNVector3(-pitch, yaw, 0)
    scene.rootNode.addChildNode(pivot)
    return scene
}

// MARK: - Шина

func tyre() -> SCNNode {
    let node = SCNNode()
    let rubber = pbr(rgb(38, 38, 42), metal: 0, rough: 0.6)
    let body = SCNNode(geometry: SCNTorus(ringRadius: 1.0, pipeRadius: 0.44))
    body.geometry!.materials = [rubber]
    (body.geometry as! SCNTorus).ringSegmentCount = 96
    (body.geometry as! SCNTorus).pipeSegmentCount = 48
    body.scale = SCNVector3(1, 1.35, 1)   // шире профиль
    node.addChildNode(body)

    // Протектор: блоки по окружности в два ряда ёлочкой.
    let block = SCNBox(width: 0.14, height: 0.4, length: 0.13, chamferRadius: 0.04)
    block.materials = [pbr(rgb(20, 20, 22), metal: 0, rough: 0.9)]
    for index in 0..<30 {
        let angle = CGFloat(index) / 30 * 2 * .pi
        for row in [-1.0, 1.0] {
            let tread = SCNNode(geometry: block)
            let holder = SCNNode()
            tread.position = SCNVector3(1.365, row * 0.25, 0)
            tread.eulerAngles = SCNVector3(0, 0, 0)
            tread.eulerAngles.x = row * 0.35
            holder.eulerAngles.y = angle + (row > 0 ? CGFloat.pi / 30 : 0)
            holder.addChildNode(tread)
            node.addChildNode(holder)
        }
    }

    // Диск: чаша, пять спиц, колпак.
    let steel = pbr(rgb(184, 188, 196), metal: 1, rough: 0.32)
    let dish = SCNNode(geometry: SCNCylinder(radius: 0.74, height: 0.5))
    dish.geometry!.materials = [pbr(rgb(60, 62, 68), metal: 1, rough: 0.45)]
    node.addChildNode(dish)
    let lip = SCNNode(geometry: SCNTube(innerRadius: 0.64, outerRadius: 0.8, height: 0.78))
    lip.geometry!.materials = [steel]
    node.addChildNode(lip)
    for index in 0..<5 {
        let spoke = SCNNode(geometry: SCNBox(width: 0.66, height: 0.12, length: 0.2, chamferRadius: 0.06))
        spoke.geometry!.materials = [steel]
        let holder = SCNNode()
        spoke.position = SCNVector3(0.34, 0.33, 0)
        holder.eulerAngles.y = CGFloat(index) / 5 * 2 * .pi
        holder.addChildNode(spoke)
        node.addChildNode(holder)
    }
    let cap = SCNNode(geometry: SCNCylinder(radius: 0.2, height: 0.82))
    cap.geometry!.materials = [steel]
    node.addChildNode(cap)

    // Колесо стоит и чуть повёрнуто лицом к зрителю.
    let stand = SCNNode()
    node.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
    stand.addChildNode(node)
    stand.eulerAngles.y = -0.62
    return stand
}

// MARK: - Звезда

func star() -> SCNNode {
    let path = NSBezierPath()
    let points = 5
    for index in 0..<(points * 2) {
        let radius: CGFloat = index % 2 == 0 ? 1.0 : 0.5
        let angle = CGFloat(index) / CGFloat(points * 2) * 2 * .pi + .pi / 2
        let point = NSPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        if index == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    path.lineJoinStyle = .round
    path.flatness = 0.005
    let shape = SCNShape(path: path, extrusionDepth: 0.42)
    shape.chamferRadius = 0.16
    shape.chamferMode = .both
    shape.materials = [pbr(rgb(255, 184, 0), metal: 0.0, rough: 0.3)]
    let node = SCNNode(geometry: shape)
    // Лежит, приподняв верхний луч к зрителю.
    node.eulerAngles = SCNVector3(-0.62, 0.25, 0.12)
    let holder = SCNNode()
    holder.addChildNode(node)
    return holder
}

// MARK: - Ключ и отвёртка

func tools() -> SCNNode {
    let root = SCNNode()
    let steel = pbr(rgb(176, 182, 192), metal: 1, rough: 0.34)

    // Рожковый ключ одним контуром: ручка и две головки с зевом.
    let outline = NSBezierPath()
    let r: CGFloat = 0.42, slot: CGFloat = 0.17, neck: CGFloat = 0.17, cy: CGFloat = 0.95
    let open = asin(slot / r), join = asin(neck / r)
    func deg(_ radians: CGFloat) -> CGFloat { radians * 180 / .pi }
    // Верхняя головка: от правого края зева по часовой до шейки.
    outline.move(to: NSPoint(x: slot, y: cy + 0.05))
    outline.line(to: NSPoint(x: slot, y: cy + r * cos(open)))
    outline.appendArc(withCenter: NSPoint(x: 0, y: cy), radius: r,
                      startAngle: 90 - deg(open), endAngle: -90 + deg(join), clockwise: true)
    outline.line(to: NSPoint(x: neck, y: -cy + r * cos(join)))
    outline.appendArc(withCenter: NSPoint(x: 0, y: -cy), radius: r,
                      startAngle: 90 - deg(join), endAngle: -90 + deg(open), clockwise: true)
    outline.line(to: NSPoint(x: slot, y: -cy - 0.05))
    outline.line(to: NSPoint(x: -slot, y: -cy - 0.05))
    outline.line(to: NSPoint(x: -slot, y: -cy - r * cos(open)))
    outline.appendArc(withCenter: NSPoint(x: 0, y: -cy), radius: r,
                      startAngle: -90 - deg(open), endAngle: 90 + deg(join), clockwise: true)
    outline.line(to: NSPoint(x: -neck, y: cy - r * cos(join)))
    outline.appendArc(withCenter: NSPoint(x: 0, y: cy), radius: r,
                      startAngle: -90 - deg(join), endAngle: 90 + deg(open), clockwise: true)
    outline.line(to: NSPoint(x: -slot, y: cy + 0.05))
    outline.close()
    outline.flatness = 0.004
    let wrench = SCNShape(path: outline, extrusionDepth: 0.24)
    wrench.chamferRadius = 0.05
    wrench.materials = [steel]
    let wrenchNode = SCNNode(geometry: wrench)
    wrenchNode.eulerAngles.z = .pi / 4
    root.addChildNode(wrenchNode)

    // Отвёртка: ручка, шейка, стержень, жало.
    let driver = SCNNode()
    let handle = SCNNode(geometry: SCNCapsule(capRadius: 0.28, height: 1.15))
    handle.geometry!.materials = [pbr(rgb(255, 92, 40), metal: 0, rough: 0.35)]
    handle.position = SCNVector3(0, -0.72, 0)
    driver.addChildNode(handle)
    let collar = SCNNode(geometry: SCNCylinder(radius: 0.17, height: 0.18))
    collar.geometry!.materials = [pbr(rgb(30, 30, 32), metal: 0, rough: 0.6)]
    collar.position = SCNVector3(0, -0.16, 0)
    driver.addChildNode(collar)
    let shaft = SCNNode(geometry: SCNCylinder(radius: 0.11, height: 1.25))
    shaft.geometry!.materials = [steel]
    shaft.position = SCNVector3(0, 0.52, 0)
    driver.addChildNode(shaft)
    let tip = SCNNode(geometry: SCNBox(width: 0.3, height: 0.24, length: 0.09, chamferRadius: 0.02))
    tip.geometry!.materials = [steel]
    tip.position = SCNVector3(0, 1.2, 0)
    driver.addChildNode(tip)
    driver.eulerAngles.z = -.pi / 4
    driver.position.z = 0.3
    root.addChildNode(driver)

    // Лежат на карте, приподняты к зрителю.
    root.eulerAngles = SCNVector3(-0.7, 0.2, 0)
    let holder = SCNNode()
    holder.addChildNode(root)
    return holder
}

// MARK: - Значки действий

/// Общая поза лежащего значка: приподнят к зрителю, чуть повёрнут.
func posed(_ node: SCNNode) -> SCNNode {
    node.eulerAngles = SCNVector3(-0.62, 0.25, 0.08)
    let holder = SCNNode()
    holder.addChildNode(node)
    return holder
}

func plate(_ color: NSColor, corner: CGFloat = 0.42) -> SCNNode {
    let box = SCNBox(width: 2, height: 2, length: 0.42, chamferRadius: 0.2)
    let path = NSBezierPath(roundedRect: NSRect(x: -1, y: -1, width: 2, height: 2), xRadius: corner, yRadius: corner)
    path.flatness = 0.004
    let shape = SCNShape(path: path, extrusionDepth: 0.42)
    shape.chamferRadius = 0.12
    shape.materials = [pbr(color, metal: 0, rough: 0.3)]
    _ = box
    return SCNNode(geometry: shape)
}

func raised(_ path: NSBezierPath, color: NSColor = .white) -> SCNNode {
    path.flatness = 0.004
    let shape = SCNShape(path: path, extrusionDepth: 0.2)
    shape.chamferRadius = 0.05
    shape.materials = [pbr(color, metal: 0, rough: 0.35)]
    let node = SCNNode(geometry: shape)
    node.position.z = 0.3
    return node
}

/// Парковка: синяя плитка с буквой P.
func parking() -> SCNNode {
    let root = plate(rgb(0, 122, 255))
    let text = SCNText(string: "P", extrusionDepth: 0.2)
    text.font = NSFont.systemFont(ofSize: 1.5, weight: .heavy)
    text.flatness = 0.01
    text.chamferRadius = 0.03
    text.materials = [pbr(.white, metal: 0, rough: 0.35)]
    let letter = SCNNode(geometry: text)
    let (lo, hi) = letter.boundingBox
    letter.position = SCNVector3(-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, 0.22)
    root.addChildNode(letter)
    return posed(root)
}

/// Маршрут: синий ромб со стрелкой поворота.
func route() -> SCNNode {
    let sign = plate(rgb(0, 122, 255), corner: 0.34)
    sign.eulerAngles.z = .pi / 4
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: -0.5, y: -0.6))
    arrow.line(to: NSPoint(x: -0.5, y: 0.1))
    arrow.curve(to: NSPoint(x: -0.15, y: 0.42), controlPoint1: NSPoint(x: -0.5, y: 0.3), controlPoint2: NSPoint(x: -0.35, y: 0.42))
    arrow.line(to: NSPoint(x: 0.2, y: 0.42))
    arrow.line(to: NSPoint(x: 0.2, y: 0.72))
    arrow.line(to: NSPoint(x: 0.75, y: 0.27))
    arrow.line(to: NSPoint(x: 0.2, y: -0.18))
    arrow.line(to: NSPoint(x: 0.2, y: 0.12))
    arrow.line(to: NSPoint(x: -0.15, y: 0.12))
    arrow.line(to: NSPoint(x: -0.2, y: 0.08))
    arrow.line(to: NSPoint(x: -0.2, y: -0.6))
    arrow.close()
    let mark = raised(arrow)
    mark.eulerAngles.z = -.pi / 4
    sign.addChildNode(mark)
    let root = SCNNode()
    root.addChildNode(sign)
    return posed(root)
}

/// Телефон: цельная зелёная трубка круглого сечения — изогнутая ручка и
/// две чашки крупнее неё, развёрнутые внутрь дуги. Без плитки и без
/// контуров: так устроены объёмные значки-эталоны (08.10.2026).
func phone() -> SCNNode {
    let root = SCNNode()
    let green = pbr(rgb(30, 175, 70), metal: 0, rough: 0.36)
    let radius: CGFloat = 1.0, from: CGFloat = 222, to: CGFloat = 318
    // Ручка — шары вплотную по дуге: гладкая гнутая «колбаса».
    let bead = SCNSphere(radius: 0.27)
    bead.segmentCount = 40
    bead.materials = [green]
    let steps = 60
    for index in 0...steps {
        let angle = (from + (to - from) * CGFloat(index) / CGFloat(steps)) * .pi / 180
        let node = SCNNode(geometry: bead)
        node.position = SCNVector3(cos(angle) * radius, sin(angle) * radius, 0)
        root.addChildNode(node)
    }
    // Чашки динамика и микрофона: приплюснутые шары, смотрят к центру дуги.
    let cup = SCNSphere(radius: 0.44)
    cup.segmentCount = 64
    cup.materials = [green]
    for degrees in [from - 6, to + 6] {
        let angle = degrees * .pi / 180
        let node = SCNNode(geometry: cup)
        node.scale = SCNVector3(1.0, 0.7, 0.86)
        node.eulerAngles.z = angle + .pi / 2
        node.position = SCNVector3(cos(angle) * (radius - 0.2), sin(angle) * (radius - 0.2), 0)
        root.addChildNode(node)
    }
    root.position = SCNVector3(0.42, 0.62, 0)
    root.eulerAngles.z = -0.6
    let holder = SCNNode()
    holder.addChildNode(root)
    return posed(holder)
}

/// Сайт: земной шар — голубой океан и выпуклые зелёные материки. Без
/// плитки, обручей и линий сетки.
func globe() -> SCNNode {
    let root = SCNNode()
    let ocean = SCNSphere(radius: 1)
    ocean.segmentCount = 96
    ocean.materials = [pbr(rgb(20, 112, 225), metal: 0, rough: 0.3)]
    root.addChildNode(SCNNode(geometry: ocean))
    let land = pbr(rgb(40, 168, 88), metal: 0, rough: 0.45)
    // Материк — приплюснутый шар, утопленный в океан: над водой остаётся
    // выпуклое пятно. Широта, долгота, размеры пятна.
    let patches: [(lat: CGFloat, lon: CGFloat, w: CGFloat, h: CGFloat)] = [
        (0.55, -0.35, 0.50, 0.36), (0.30, -0.10, 0.34, 0.30), (0.05, 0.02, 0.30, 0.42),
        (-0.35, 0.10, 0.26, 0.34), (0.62, 0.55, 0.46, 0.30), (0.25, 0.75, 0.30, 0.26),
        (-0.15, -0.75, 0.24, 0.40), (0.50, -1.0, 0.36, 0.28), (-0.55, 0.85, 0.28, 0.20),
    ]
    for patch in patches {
        let blob = SCNSphere(radius: 1)
        blob.segmentCount = 48
        blob.materials = [land]
        let node = SCNNode(geometry: blob)
        node.scale = SCNVector3(patch.w * 0.85, patch.h * 0.85, 0.12)
        let pivot = SCNNode()
        node.position = SCNVector3(0, 0, 0.905)
        pivot.addChildNode(node)
        pivot.eulerAngles = SCNVector3(-patch.lat, patch.lon, 0)
        root.addChildNode(pivot)
    }
    root.eulerAngles = SCNVector3(0.15, -0.2, 0.3)
    let holder = SCNNode()
    holder.addChildNode(root)
    return holder
}

/// Плюс: зелёный крест с мягкими рёбрами.
func plus() -> SCNNode {
    let path = NSBezierPath()
    let a: CGFloat = 0.32, b: CGFloat = 1.0
    for (x, y) in [(-a, b), (a, b), (a, a), (b, a), (b, -a), (a, -a), (a, -b), (-a, -b), (-a, -a), (-b, -a), (-b, a), (-a, a)] {
        if path.isEmpty { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
    }
    path.close()
    path.lineJoinStyle = .round
    let shape = SCNShape(path: path, extrusionDepth: 0.5)
    shape.chamferRadius = 0.14
    shape.materials = [pbr(rgb(52, 199, 89), metal: 0, rough: 0.28)]
    return posed(SCNNode(geometry: shape))
}

// MARK: - Булавка

/// Стоит прямо: остриё — самая нижняя точка кадра и по центру, на него
/// смотрит якорь метки. Тени нет по той же причине.
func pin() -> SCNNode {
    let root = SCNNode()
    let head = SCNNode(geometry: SCNSphere(radius: 0.62))
    (head.geometry as! SCNSphere).segmentCount = 64
    head.geometry!.materials = [pbr(rgb(255, 59, 48), metal: 0, rough: 0.22)]
    head.position = SCNVector3(0, 1.75, 0)
    root.addChildNode(head)
    let needle = SCNNode(geometry: SCNCone(topRadius: 0.085, bottomRadius: 0.0, height: 1.7))
    needle.geometry!.materials = [pbr(rgb(176, 182, 192), metal: 1, rough: 0.3)]
    needle.position = SCNVector3(0, 0.55, 0)
    root.addChildNode(needle)
    // Центр модели — в центр кадра, иначе шляпка упирается в край.
    root.position.y = -1.0
    let holder = SCNNode()
    holder.addChildNode(root)
    return holder
}

// MARK: - Рендер

let device = MTLCreateSystemDefaultDevice()!
for (name, node, distance) in [("tyre", tyre(), 10.5), ("star", star(), 8.2), ("service", tools(), 8.6),
                               ("pin", pin(), 12.5), ("parking", parking(), 9.5), ("route", route(), 11.5),
                               ("phone", phone(), 9.0), ("globe", globe(), 8.6), ("plus", plus(), 9.0)]
    as [(String, SCNNode, CGFloat)] {
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = makeScene(node, yaw: 0.0, pitch: 0.5, distance: distance, shadow: name != "pin")
    renderer.pointOfView = renderer.scene!.rootNode.childNodes.last!.childNodes.first!
    let image = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side),
                                  antialiasingMode: .multisampling4X)
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    print(name, "ok")
}
