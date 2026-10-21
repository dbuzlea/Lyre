//
//  GramophoneStage.swift
//  Lyre
//

import SceneKit
import SwiftUI
import UIKit

// MARK: - Gramophone Stage
//
// The gramophone in 3D, standing on a table: built in code from boxes, turned parts and
// a swept horn (see GramophoneMesh), lit by a warm room, in the chosen design and
// finish. Measurements are in metres, about life size:
//
//   plinth   bun feet, a base, the drawer the records are kept in, a moulding
//   body     the box, its front panel with the play switch, the plate showing the song
//            playing, and the speed knob; the crank on its right-hand side
//   deck     the turntable and the tonearm on top, under the lid propped open
//   horn     the horn design's fluted bell, rising from the arm's pivot at the back
//            (the cabinet design has turned columns and a grille instead)
//
// and, on the table to its left, a bin of the records waiting in Up Next, standing on
// end with their covers out; the ones flipped past lean forward over its front, as in a
// record shop (`setRackIndex`, `setRackPull`).
//
// The camera has four shots, and moves between them (GramophoneCameraPath):
//
//   front      square on to the front panel, a little from above, so the record shows
//              on the deck
//   turntable  straight down on the record, placed so the record lies exactly where
//              the 2D turntable draws its own, which takes over there for the tonearm
//              and its gestures
//   drawer     straight down into the drawer, pulled out, where the records are kept;
//              the crate (the records, playlists and podcasts) is shown over it
//   rack       round to the bin's front, a little from above, onto the record at the
//              front of it
//
// A record put on comes out of its sleeve and down onto the platter, and the arm swings
// over and lowers onto it (`putRecord`), before the 2D turntable takes over.
//
// The player puts SwiftUI controls over the machine's parts in front (`onHotspots`
// says where they are on screen), so they work with VoiceOver and the UI tests.

/// The parts of the machine a finger can work in front, and the records in the open
/// drawer (`stack`, the one on top).
enum GramophoneHotspot: Hashable, CaseIterable {
    case playSwitch, plate, speed, crank, drawer, rack, turntable, stack, rackRecord
}

/// Where the camera can be.
enum GramophoneShot: Hashable {
    case front, turntable, drawer, rack
}

@MainActor
final class GramophoneStage {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private weak var view: SCNView?

    /// The shot the camera is at, or on its way to.
    private(set) var shot: GramophoneShot = .front
    /// Where the parts are on screen, in window coordinates, whenever the camera
    /// settles in front.
    var onHotspots: (([GramophoneHotspot: CGRect]) -> Void)?

    static let recordRadius: Float = 0.18
    /// The record's centre on the deck: x across, z toward the front.
    static let platterCenter = SIMD2<Float>(-0.035, 0.03)
    /// How far the drawer pulls out.
    static let drawerTravel: Float = 0.4
    static let fieldOfView: Float = 34

    /// The tonearm, in the deck's plane (x across, y toward the front), laid out as the
    /// 2D turntable lays it out, so the two agree.
    static var armGeometry: TonearmGeometry {
        TonearmGeometry(center: CGPoint(x: CGFloat(platterCenter.x), y: CGFloat(platterCenter.y)),
                        radius: CGFloat(recordRadius))
    }

    private var model: GramophoneModel = .horn
    private var finish: GramophoneFinish = .mahogany
    private var theme: GramophoneTheme { finish.theme }

    // The machine's moving parts.
    private let machine = SCNNode()
    private let spinner = SCNNode()
    private let recordNode = SCNNode()
    private let armYaw = SCNNode()
    private let armLift = SCNNode()
    private let switchLever = SCNNode()
    private let speedKnob = SCNNode()
    private let crank = SCNNode()
    private let drawer = SCNNode()
    private let drawerStack = SCNNode()
    /// The records in the drawer, top first, and the covers on them.
    private var stackSleeves: [SCNNode] = []
    private var stackArt: [UIImage?] = []
    private let rack = SCNNode()
    /// The bin's records in view, by their place in Up Next.
    private var rackSleeves: [Int: SCNNode] = [:]
    private var horn: SCNNode?
    private var hotspotNodes: [GramophoneHotspot: SCNNode] = [:]
    private var deckY: Float = 0
    private var recordTopY: Float { deckY + 0.018 }

    // The finish.
    private let wood = SCNMaterial(), trim = SCNMaterial(), metal = SCNMaterial()
    private let felt = SCNMaterial(), ebony = SCNMaterial(), tableTop = SCNMaterial(), cloth = SCNMaterial()
    private let plateCard = SCNMaterial(), switchPlate = SCNMaterial(), speedPlate = SCNMaterial()
    private let recordFace = SCNMaterial(), shellac = SCNMaterial(), hornInside = SCNMaterial()

    // What's shown, kept to show again when the machine is rebuilt.
    private var record: RecordOnPlatter?
    private var labelImage: UIImage?
    private var plateText = ("", "")
    private var armAngle = GramophoneStage.armGeometry.restAngle
    private var isArmLifted = false
    private var isSpinning = false
    private var isSwitchOn = false
    private var crankDegrees = 0.0
    private(set) var isDrawerOpen = false
    /// Up Next, by its songs' ids, and their covers.
    private var rackIDs: [String] = []
    private var rackArt: [String: UIImage] = [:]
    /// The record at the front of the bin: the ones before it are flipped forward.
    private(set) var rackIndex = 0
    /// A flip under way: toward the next record (up to 1) or back to the one before
    /// (down to -1).
    private var rackPull: Float = 0
    /// The front record pushed aside, to show the way to take it out.
    private var rackSlide: Float = 0
    private var speedTurn: Float = 0
    private var isTurntableHidden = false
    private var isDrawerStackHidden = false
    /// A record on its way from its sleeve to the platter; the platter's own record
    /// stays hidden till it lands.
    private var isPutting = false

    // The camera's shots.
    private var viewSize: CGSize = .zero
    private var insets: (top: CGFloat, bottom: CGFloat) = (0, 0)
    /// The 2D turntable's record, in the view's points.
    private var overheadRecord: (center: CGPoint, radius: CGFloat)?
    private var poses: [GramophoneShot: GramophoneCameraPose] = [:]
    private var driver: CameraDriver?

    init() {
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(Self.fieldOfView)
        camera.projectionDirection = .horizontal
        camera.zNear = 0.02
        camera.zFar = 30
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3(0.4, 0.9, 2.2)
        scene.rootNode.addChildNode(cameraNode)

        scene.lightingEnvironment.contents = GramophoneTextures.room()
        scene.lightingEnvironment.intensity = 0.9
        addLights()

        for material in [wood, trim, metal, felt, ebony, tableTop, cloth, plateCard, switchPlate, speedPlate,
                         recordFace, shellac, hornInside] {
            material.lightingModel = .physicallyBased
        }
        scene.rootNode.addChildNode(machine)
        applyFinish()
        build()
    }

    /// Shows the machine in `view`.
    func attach(_ view: SCNView) {
        self.view = view
        view.scene = scene
        view.pointOfView = cameraNode
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isUserInteractionEnabled = false
        applyFrameRate()
    }

    // MARK: - Frame Rate

    /// Until when something besides the record is moving.
    private var smoothUntil: Date = .distantPast

    /// Drawn 60 times a second for `seconds`, while something moves.
    private func boost(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        smoothUntil = max(smoothUntil, Date().addingTimeInterval(seconds + 0.1))
        applyFrameRate()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.15) { [weak self] in self?.applyFrameRate() }
    }

    /// 30 frames a second while all that moves is the record turning (a slow, even turn
    /// looks the same at 30 as at 60, for half the work), 60 while the camera, the arm,
    /// the drawer or a record moves. 30 throughout in Low Power Mode.
    private func applyFrameRate() {
        let moving = driver != nil || Date() < smoothUntil
        view?.preferredFramesPerSecond = moving && !ProcessInfo.processInfo.isLowPowerModeEnabled ? 60 : 30
    }

    // MARK: - Design and Finish

    func configure(model: GramophoneModel, finish: GramophoneFinish) {
        let finishChanged = finish != self.finish
        let modelChanged = model != self.model
        self.model = model
        self.finish = finish
        if finishChanged {
            applyFinish()
            setPlate(title: plateText.0, subtitle: plateText.1, force: true)
        }
        if modelChanged {
            build()
            updatePoses()
        }
    }

    private func applyFinish() {
        let grain = GramophoneTextures.woodGrain(theme, seed: 11)
        wood.diffuse.contents = grain
        wood.roughness.contents = finish == .lacquer ? 0.3 : 0.58
        trim.diffuse.contents = GramophoneTextures.woodGrain(theme, seed: 23)
        wood.multiply.contents = UIColor(white: 0.85, alpha: 1)
        trim.multiply.contents = UIColor(white: 0.62, alpha: 1)
        trim.roughness.contents = finish == .lacquer ? 0.32 : 0.6
        for material in [wood, trim] {
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
        }
        metal.diffuse.contents = UIColor(theme.metal)
        metal.metalness.contents = 1
        metal.roughness.contents = 0.3
        hornInside.diffuse.contents = UIColor(theme.metal)
        hornInside.metalness.contents = 0.85
        hornInside.roughness.contents = 0.38
        felt.diffuse.contents = UIColor(theme.felt)
        felt.roughness.contents = 1
        ebony.diffuse.contents = UIColor(white: 0.05, alpha: 1)
        ebony.roughness.contents = 0.3
        cloth.diffuse.contents = UIColor(red: 0.14, green: 0.09, blue: 0.06, alpha: 1)
        cloth.roughness.contents = 1
        shellac.diffuse.contents = UIColor(white: 0.035, alpha: 1)
        shellac.roughness.contents = 0.28
        recordFace.roughness.contents = 0.45
        recordFace.multiply.contents = UIColor(white: 0.8, alpha: 1)
        plateCard.roughness.contents = 0.85
        for (material, image) in [(switchPlate, GramophoneTextures.switchPlate(theme: theme)),
                                  (speedPlate, GramophoneTextures.speedPlate(theme: theme))] {
            material.diffuse.contents = image
            material.metalness.contents = 0.65
            material.roughness.contents = 0.35
        }
        // The table, the same dark wood whatever the machine's finish.
        tableTop.diffuse.contents = GramophoneTextures.woodGrain(GramophoneFinish.walnut.theme, seed: 5)
        tableTop.multiply.contents = UIColor(white: 0.32, alpha: 1)
        tableTop.roughness.contents = 0.55
        tableTop.diffuse.wrapS = .repeat
        tableTop.diffuse.wrapT = .repeat
        tableTop.diffuse.contentsTransform = SCNMatrix4MakeScale(5, 5, 1)
    }

    private func addLights() {
        // The lamp, to the left in front and not far above, casting the machine's shadow on the table.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 420
        key.color = UIColor(red: 1, green: 0.93, blue: 0.82, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowSampleCount = 16
        key.shadowRadius = 6
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = UIColor(white: 0, alpha: 0.55)
        key.orthographicScale = 1.1
        key.automaticallyAdjustsShadowProjection = true
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = SIMD3(-0.9, 1.1, 1.7)
        keyNode.simdLook(at: SIMD3(0, 0.3, 0))
        scene.rootNode.addChildNode(keyNode)

        // A warm fill from the right, and a light behind to pick out the horn's edge.
        let fill = SCNLight()
        fill.type = .omni
        fill.intensity = 15
        fill.color = UIColor(red: 1, green: 0.78, blue: 0.55, alpha: 1)
        fill.attenuationStartDistance = 0.5
        fill.attenuationEndDistance = 3
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.simdPosition = SIMD3(1.4, 0.9, 0.8)
        scene.rootNode.addChildNode(fillNode)

        let rim = SCNLight()
        rim.type = .omni
        rim.intensity = 25
        rim.color = UIColor(red: 1, green: 0.85, blue: 0.65, alpha: 1)
        rim.attenuationStartDistance = 0.5
        rim.attenuationEndDistance = 3
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.simdPosition = SIMD3(0.3, 1.4, -1.2)
        scene.rootNode.addChildNode(rimNode)
    }

    // MARK: - Building the Machine

    private func build() {
        machine.childNodes.forEach { $0.removeFromParentNode() }
        hotspotNodes = [:]
        let bodyHeight: Float = model == .horn ? 0.21 : 0.27
        let bodyBottom: Float = 0.118
        let bodyTop = bodyBottom + bodyHeight
        deckY = bodyTop + 0.014

        // The table.
        add(box(3.2, 0.04, 2.6, material: tableTop), at: SIMD3(0, -0.04, 0.5))

        // The plinth: bun feet, the base, the drawer, a moulding.
        let bun = GramophoneMesh.lathe([SIMD2(0, 0), SIMD2(0.016, 0.001), SIMD2(0.026, 0.009),
                                        SIMD2(0.024, 0.017), SIMD2(0.018, 0.022), SIMD2(0, 0.022)], segments: 24)
        for x: Float in [-0.235, 0.235] {
            for z: Float in [-0.235, 0.235] {
                add(node(bun, ebony), at: SIMD3(x, 0, z))
            }
        }
        add(box(0.54, 0.028, 0.54, chamfer: 0.006, material: trim), at: SIMD3(0, 0.022, 0))
        add(box(0.5, 0.055, 0.5, chamfer: 0.003, material: wood), at: SIMD3(0, 0.05, 0))
        buildDrawer()
        add(box(0.48, 0.013, 0.48, chamfer: 0.004, material: trim), at: SIMD3(0, 0.105, 0))

        // The body and the lip around the deck.
        add(box(0.44, bodyHeight, 0.44, chamfer: 0.004, material: wood), at: SIMD3(0, bodyBottom, 0))
        add(box(0.465, 0.014, 0.465, chamfer: 0.004, material: trim), at: SIMD3(0, bodyTop, 0))

        buildFront(bottom: bodyBottom, height: bodyHeight)
        buildCrank(at: SIMD3(0.22, bodyBottom + bodyHeight * 0.52, 0.03))
        buildTurntable()
        buildArm()
        buildLid()
        if model == .horn {
            buildHorn()
        } else {
            horn = nil
            buildColumns(bottom: bodyBottom, height: bodyHeight)
        }
        buildRack()

        // Show what was shown.
        setRecordTexture()
        recordNode.isHidden = record == nil || isPutting
        setArm(angle: armAngle, lifted: isArmLifted, animated: false)
        setSwitch(on: isSwitchOn, animated: false)
        setCrank(degrees: crankDegrees)
        setDrawer(open: isDrawerOpen, animated: false)
        layOutRack(animated: false)
        setSpinning(isSpinning)
        speedKnob.simdEulerAngles.z = speedTurn
        setTurntableHidden(isTurntableHidden)
        setDrawerStackHidden(isDrawerStackHidden)
        if driver == nil { applyShot() }
    }

    /// The drawer the records are kept in: a tray running the depth of the plinth, with
    /// a stack of records in their sleeves lying in it.
    private func buildDrawer() {
        drawer.childNodes.forEach { $0.removeFromParentNode() }
        drawerStack.childNodes.forEach { $0.removeFromParentNode() }
        // Placed by the middle of its front.
        let depth: Float = 0.42
        let front = box(0.44, 0.046, 0.014, chamfer: 0.002, material: trim)
        front.simdPosition = SIMD3(0, -0.023, 0)
        drawer.addChildNode(front)
        let knob = node(GramophoneMesh.lathe([SIMD2(0.004, 0), SIMD2(0.004, 0.006), SIMD2(0.009, 0.01),
                                              SIMD2(0.009, 0.014), SIMD2(0, 0.016)], segments: 24), metal)
        knob.simdEulerAngles.x = .pi / 2
        knob.simdPosition = SIMD3(0, 0, 0.007)
        drawer.addChildNode(knob)
        let floor = box(0.42, 0.006, depth, material: trim)
        floor.simdPosition = SIMD3(0, -0.0215, -0.007 - depth / 2)
        drawer.addChildNode(floor)
        for x: Float in [-0.205, 0.205] {
            let side = box(0.01, 0.04, depth, material: wood)
            side.simdPosition = SIMD3(x, -0.0215, -0.007 - depth / 2)
            drawer.addChildNode(side)
        }
        let back = box(0.42, 0.04, 0.01, material: wood)
        back.simdPosition = SIMD3(0, -0.0215, -0.012 - depth)
        drawer.addChildNode(back)

        // The records, lying in a slightly untidy stack, the top one square; the stack
        // shown over them in the drawer lies the same way (RecordStackView).
        let colors: [UIColor] = [UIColor(white: 0.08, alpha: 1), UIColor(red: 0.62, green: 0.47, blue: 0.3, alpha: 1),
                                 UIColor(red: 0.86, green: 0.81, blue: 0.7, alpha: 1), UIColor(red: 0.14, green: 0.2, blue: 0.32, alpha: 1),
                                 UIColor(red: 0.5, green: 0.12, blue: 0.1, alpha: 1), UIColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 1)]
        stackSleeves = []
        for (layer, color) in colors.enumerated() {
            let depthInStack = colors.count - 1 - layer
            let lie = Self.stackLie(depthInStack)
            let sleeve = box(Self.stackSleeveSide, 0.004, Self.stackSleeveSide, chamfer: 0.001, material: Self.paper(color))
            sleeve.simdPosition = SIMD3(lie.x, Float(layer) * 0.0045, lie.z)
            sleeve.simdEulerAngles.y = lie.angle
            drawerStack.addChildNode(sleeve)
            stackSleeves.insert(sleeve, at: 0)
        }
        let top = SCNNode(geometry: SCNBox(width: CGFloat(Self.stackSleeveSide), height: 0.002,
                                           length: CGFloat(Self.stackSleeveSide), chamferRadius: 0))
        top.simdPosition = SIMD3(0, Float(colors.count) * 0.0045, 0)
        top.isHidden = true
        drawerStack.addChildNode(top)
        hotspotNodes[.stack] = top
        drawerStack.simdPosition = SIMD3(0, -0.0155, -0.007 - depth / 2)
        drawerStack.isHidden = isDrawerStackHidden
        drawer.addChildNode(drawerStack)
        setDrawerStack(art: stackArt)
        drawer.simdPosition = SIMD3(0, 0.0775, 0.25 + (isDrawerOpen ? Self.drawerTravel : 0))
        machine.addChildNode(drawer)
        addHotspot(.drawer, size: SIMD3(0.44, 0.06, 0.04), at: SIMD3(0, 0.0775, 0.26))
    }

    /// A side of a record's sleeve in the drawer.
    static let stackSleeveSide: Float = 0.31

    /// How the record `depth` down the stack lies (0 on top): off the top one's
    /// middle sideways (x) and towards the front (z), and turned round (radians,
    /// anticlockwise from above).
    static func stackLie(_ depth: Int) -> (x: Float, z: Float, angle: Float) {
        let lies: [(Float, Float, Float)] = [(0, 0, 0), (-0.008, 0.006, 0.05), (0.009, -0.004, -0.06),
                                             (-0.004, -0.008, 0.035), (0.007, 0.007, -0.045), (-0.006, 0, 0.06)]
        let lie = lies[min(depth, lies.count - 1)]
        return (lie.0, lie.1, lie.2)
    }

    /// Paper in a colour: a record sleeve.
    private static func paper(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = 0.8
        return material
    }

    /// The front panel: the play switch, the plate with the song playing, the speed
    /// knob, and the design's decoration.
    private func buildFront(bottom: Float, height: Float) {
        let face: Float = 0.22
        let controlsY = bottom + height * (model == .horn ? 0.52 : 0.68)

        // A raised panel the controls sit on, with a moulding round it.
        let panelHeight: Float = model == .horn ? height * 0.74 : 0.13
        add(box(0.4, panelHeight, 0.006, chamfer: 0.002, material: trim), at: SIMD3(0, controlsY - panelHeight / 2, face))
        for (w, h, x, y) in [(0.41, 0.008, 0, controlsY + panelHeight / 2), (0.41, 0.008, 0, controlsY - panelHeight / 2 - 0.008),
                             (0.008, panelHeight + 0.016, -0.205, controlsY - panelHeight / 2 - 0.008),
                             (0.008, panelHeight + 0.016, 0.205, controlsY - panelHeight / 2 - 0.008)] as [(Float, Float, Float, Float)] {
            add(box(w, h, 0.01, chamfer: 0.002, material: wood), at: SIMD3(x, y, face))
        }

        // The plate: a brass frame with the card in it.
        add(box(0.215, 0.094, 0.01, chamfer: 0.003, material: metal), at: SIMD3(0, controlsY - 0.047, face + 0.006))
        let card = SCNNode(geometry: SCNPlane(width: 0.192, height: 0.074))
        card.geometry?.firstMaterial = plateCard
        card.simdPosition = SIMD3(0, controlsY, face + 0.0113)
        machine.addChildNode(card)
        addHotspot(.plate, size: SIMD3(0.215, 0.094, 0.02), at: SIMD3(0, controlsY, face + 0.01))

        // The play switch: a lever on a plate, thrown left to stop, right to start.
        add(box(0.07, 0.064, 0.004, chamfer: 0.002, material: switchPlate), at: SIMD3(-0.158, controlsY - 0.032, face + 0.006))
        switchLever.childNodes.forEach { $0.removeFromParentNode() }
        switchLever.simdPosition = SIMD3(-0.158, controlsY - 0.02, face + 0.012)
        let boss = node(SCNCylinder(radius: 0.009, height: 0.008), metal)
        boss.simdEulerAngles.x = .pi / 2
        switchLever.addChildNode(boss)
        let stem = node(SCNCylinder(radius: 0.0032, height: 0.03), metal)
        stem.simdPosition = SIMD3(0, 0.015, 0.004)
        switchLever.addChildNode(stem)
        let ball = node(SCNSphere(radius: 0.0068), ebony)
        ball.simdPosition = SIMD3(0, 0.032, 0.004)
        switchLever.addChildNode(ball)
        machine.addChildNode(switchLever)
        addHotspot(.playSwitch, size: SIMD3(0.075, 0.075, 0.03), at: SIMD3(-0.158, controlsY, face + 0.01))

        // The speed knob, on its marked plate.
        let dial = node(GramophoneMesh.disc(radius: 0.034, segments: 64), speedPlate)
        dial.simdEulerAngles.x = .pi / 2
        dial.simdPosition = SIMD3(0.158, controlsY, face + 0.0065)
        machine.addChildNode(dial)
        speedKnob.childNodes.forEach { $0.removeFromParentNode() }
        speedKnob.simdPosition = SIMD3(0.158, controlsY, face + 0.006)
        let knob = node(GramophoneMesh.lathe([SIMD2(0, 0), SIMD2(0.018, 0), SIMD2(0.018, 0.004), SIMD2(0.016, 0.012),
                                              SIMD2(0.016, 0.012), SIMD2(0.012, 0.016), SIMD2(0, 0.017)], segments: 36), metal)
        knob.simdEulerAngles.x = .pi / 2
        speedKnob.addChildNode(knob)
        let pointer = node(SCNBox(width: 0.003, height: 0.012, length: 0.003, chamferRadius: 0.001), ebony)
        pointer.simdPosition = SIMD3(0, 0.008, 0.017)
        speedKnob.addChildNode(pointer)
        machine.addChildNode(speedKnob)
        addHotspot(.speed, size: SIMD3(0.075, 0.075, 0.03), at: SIMD3(0.158, controlsY, face + 0.01))

        if model == .cabinet {
            // The grille below the controls: cloth behind wooden slats.
            let grilleY = bottom + height * 0.3
            let grille = SCNNode(geometry: SCNPlane(width: 0.36, height: 0.09))
            grille.geometry?.firstMaterial = cloth
            grille.simdPosition = SIMD3(0, grilleY, face + 0.001)
            machine.addChildNode(grille)
            for slat in 0..<13 {
                let x = -0.168 + Float(slat) * 0.028
                add(box(0.007, 0.09, 0.008, chamfer: 0.002, material: trim), at: SIMD3(x, grilleY - 0.045, face + 0.002))
            }
            for y in [grilleY + 0.045, grilleY - 0.053] {
                add(box(0.38, 0.008, 0.012, chamfer: 0.002, material: wood), at: SIMD3(0, y, face + 0.001))
            }
        } else {
            // Brass rosettes at the panel's corners.
            let rosette = GramophoneMesh.lathe([SIMD2(0, 0), SIMD2(0.011, 0), SIMD2(0.011, 0.002),
                                                SIMD2(0.006, 0.005), SIMD2(0, 0.006)], segments: 24)
            for x: Float in [-0.19, 0.19] {
                for y in [controlsY + panelHeight / 2 - 0.016, controlsY - panelHeight / 2 + 0.016] {
                    let node = node(rosette, metal)
                    node.simdEulerAngles.x = .pi / 2
                    node.simdPosition = SIMD3(x, y, face + 0.006)
                    machine.addChildNode(node)
                }
            }
        }
    }

    /// The winding crank on the right-hand side: a brass escutcheon, the crank turning
    /// in it, and its wooden handle.
    private func buildCrank(at hub: SIMD3<Float>) {
        let plate = node(GramophoneMesh.lathe([SIMD2(0, 0), SIMD2(0.024, 0), SIMD2(0.024, 0.003),
                                               SIMD2(0.016, 0.007), SIMD2(0, 0.008)], segments: 32), metal)
        plate.simdEulerAngles.z = -.pi / 2
        plate.simdPosition = hub
        machine.addChildNode(plate)

        crank.childNodes.forEach { $0.removeFromParentNode() }
        crank.simdPosition = hub + SIMD3(0.016, 0, 0)
        let shaft = node(SCNCylinder(radius: 0.005, height: 0.016), metal)
        shaft.simdEulerAngles.z = .pi / 2
        crank.addChildNode(shaft)
        let arm = box(0.006, 0.08, 0.012, chamfer: 0.002, material: metal)
        arm.simdPosition = SIMD3(0.008, 0, 0)
        crank.addChildNode(arm)
        let handle = node(GramophoneMesh.lathe([SIMD2(0, 0), SIMD2(0.007, 0), SIMD2(0.011, 0.012),
                                                SIMD2(0.012, 0.03), SIMD2(0.009, 0.045), SIMD2(0, 0.048)], segments: 24), ebony)
        handle.simdEulerAngles.z = -.pi / 2
        handle.simdPosition = SIMD3(0.011, 0.074, 0)
        crank.addChildNode(handle)
        machine.addChildNode(crank)
        addHotspot(.crank, size: SIMD3(0.09, 0.2, 0.2), at: hub + SIMD3(0.03, 0, 0))
    }

    private func buildTurntable() {
        let center = SIMD3(Self.platterCenter.x, deckY, Self.platterCenter.y)
        let r = Self.recordRadius
        let platter = node(GramophoneMesh.lathe([SIMD2(0, 0), SIMD2(r * 1.035, 0), SIMD2(r * 1.06, 0.003),
                                                 SIMD2(r * 1.06, 0.014), SIMD2(r * 1.045, 0.016), SIMD2(r * 1.01, 0.016),
                                                 SIMD2(0, 0.016)], segments: 96), metal)
        platter.simdPosition = center
        machine.addChildNode(platter)
        let mat = node(GramophoneMesh.disc(radius: r * 1.012, segments: 96), felt)
        mat.simdPosition = center + SIMD3(0, 0.0162, 0)
        machine.addChildNode(mat)

        spinner.childNodes.forEach { $0.removeFromParentNode() }
        spinner.simdPosition = center
        recordNode.childNodes.forEach { $0.removeFromParentNode() }
        let edge = node(SCNCylinder(radius: CGFloat(r), height: 0.0016), shellac)
        edge.simdPosition = SIMD3(0, 0.0168, 0)
        recordNode.addChildNode(edge)
        let face = node(GramophoneMesh.disc(radius: r, segments: 128), recordFace)
        face.simdPosition = SIMD3(0, 0.0177, 0)
        recordNode.addChildNode(face)
        spinner.addChildNode(recordNode)
        let spindle = node(SCNCylinder(radius: 0.004, height: 0.014), metal)
        spindle.simdPosition = SIMD3(0, 0.022, 0)
        spinner.addChildNode(spindle)
        machine.addChildNode(spinner)

        addHotspot(.turntable, size: SIMD3(r * 2.3, 0.08, r * 2.3), at: center + SIMD3(0, 0.03, 0))
    }

    /// The tonearm: its pivot behind the record to the right, a tapering tube, and the
    /// soundbox with the needle under it.
    private func buildArm() {
        let geometry = Self.armGeometry
        let pivot = SIMD3(Float(geometry.pivot.x), deckY, Float(geometry.pivot.y))
        let base = node(GramophoneMesh.lathe([SIMD2(0, 0), SIMD2(0.03, 0), SIMD2(0.03, 0.006), SIMD2(0.021, 0.012),
                                              SIMD2(0.016, 0.03), SIMD2(0.019, 0.034), SIMD2(0, 0.037)], segments: 40), metal)
        base.simdPosition = pivot
        machine.addChildNode(base)

        let length = Float(geometry.armLength)
        armYaw.childNodes.forEach { $0.removeFromParentNode() }
        armLift.childNodes.forEach { $0.removeFromParentNode() }
        armYaw.simdPosition = SIMD3(pivot.x, recordTopY + 0.024, pivot.z)
        let tube = node(GramophoneMesh.lathe([SIMD2(0.0075, 0), SIMD2(0.0075, 0.01), SIMD2(0.005, length)], segments: 24), metal)
        tube.simdEulerAngles.z = -.pi / 2
        armLift.addChildNode(tube)
        let soundbox = SCNNode()
        soundbox.simdPosition = SIMD3(length, -0.01, 0)
        let shell = node(SCNCylinder(radius: 0.023, height: 0.01), metal)
        soundbox.addChildNode(shell)
        let diaphragm = node(GramophoneMesh.disc(radius: 0.017, segments: 40), ebony)
        diaphragm.simdPosition = SIMD3(0, 0.0052, 0)
        soundbox.addChildNode(diaphragm)
        let needle = node(SCNCone(topRadius: 0.0016, bottomRadius: 0, height: 0.012), metal)
        needle.simdPosition = SIMD3(0, -0.009, 0)
        soundbox.addChildNode(needle)
        armLift.addChildNode(soundbox)
        armYaw.addChildNode(armLift)
        machine.addChildNode(armYaw)
    }

    /// The lid, hinged at the back and propped open, leaning back a little.
    private func buildLid() {
        let hinge = SCNNode()
        hinge.simdPosition = SIMD3(0, deckY, -0.2325)
        let lid = box(0.465, 0.016, 0.465, chamfer: 0.005, material: wood)
        lid.simdPosition = SIMD3(0, 0, 0.2325)
        hinge.addChildNode(lid)
        let panel = box(0.39, 0.003, 0.39, chamfer: 0.001, material: trim)
        panel.simdPosition = SIMD3(0, -0.003, 0.2325)
        hinge.addChildNode(panel)
        hinge.simdEulerAngles.x = -105 * .pi / 180
        machine.addChildNode(hinge)
    }

    /// The horn, rising from the arm's pivot, back and up, then curving forward into
    /// the bell.
    private func buildHorn() {
        let pivot = Self.armGeometry.pivot
        let x = Float(pivot.x), z = Float(pivot.y), y = deckY
        let shape = GramophoneMesh.horn(spine: [
            SIMD3(x, y + 0.03, z),
            SIMD3(x + 0.006, y + 0.11, z - 0.03),
            SIMD3(x - 0.004, y + 0.21, z - 0.07),
            SIMD3(x - 0.05, y + 0.32, z - 0.055),
            SIMD3(x - 0.13, y + 0.41, z + 0.02),
            SIMD3(x - 0.2, y + 0.48, z + 0.08),
        ], throat: 0.013, mouth: 0.18)
        let node = SCNNode()
        node.addChildNode(self.node(shape.outer, metal))
        node.addChildNode(self.node(shape.inner, hornInside))
        // A collar where the neck meets the pivot.
        let collar = self.node(GramophoneMesh.lathe([SIMD2(0.017, 0), SIMD2(0.019, 0.004), SIMD2(0.019, 0.016),
                                                     SIMD2(0.016, 0.02)], segments: 32), metal)
        collar.simdPosition = SIMD3(x, y + 0.03, z)
        node.addChildNode(collar)
        machine.addChildNode(node)
        horn = node
    }

    /// The cabinet design's turned columns at the front corners.
    private func buildColumns(bottom: Float, height: Float) {
        let points: [(Float, Float)] = [
            (0, 0), (0.02, 0), (0.02, 0.06), (0.015, 0.08), (0.015, 0.12), (0.023, 0.2), (0.026, 0.32),
            (0.02, 0.45), (0.013, 0.5), (0.016, 0.55), (0.022, 0.65), (0.025, 0.75), (0.02, 0.85),
            (0.015, 0.9), (0.02, 0.94), (0.02, 1), (0, 1),
        ]
        let column = GramophoneMesh.lathe(points.map { SIMD2($0.0, $0.1 * height) }, segments: 32)
        for x: Float in [-0.218, 0.218] {
            add(node(column, trim), at: SIMD3(x, bottom, 0.218))
        }
    }

    /// Where the bin stands: on the table to the left of the machine, its front turned
    /// out to the left and forward.
    static let rackPosition = SIMD3<Float>(-0.47, 0, -0.08)
    static let rackYaw: Float = -0.93
    /// A side of a record's sleeve in the bin: a ten-inch record's.
    static let rackSleeveSide: Float = 0.24
    /// Where the record at the front of the bin stands, along the bin.
    private static let rackFrontZ: Float = 0.05
    /// The bin, inside: its floor, how long it is, and its low front wall, which
    /// records flipped forward lie over.
    static let rackFloor: Float = 0.014
    static let rackLength: Float = 0.22
    static let rackWallHeight: Float = 0.06
    static let rackWallThickness: Float = 0.012
    /// The front wall's inner face (along the bin) and its top.
    static var rackWallInside: Float { rackLength / 2 - rackWallThickness / 2 }
    static var rackWallTop: Float { rackFloor + rackWallHeight }

    /// Up Next's records, standing on end in a bin, covers to its front (its +z).
    private func buildRack() {
        rack.childNodes.forEach { $0.removeFromParentNode() }
        rackSleeves = [:]
        rack.simdPosition = Self.rackPosition
        rack.simdEulerAngles.y = Self.rackYaw
        let width: Float = 0.27, length = Self.rackLength, floor = Self.rackFloor
        rack.addChildNode(box(width + 0.012, floor, length + 0.012, chamfer: 0.003, material: trim))
        for x in [-width / 2, width / 2] {
            let side = box(0.012, 0.1, length, chamfer: 0.002, material: wood)
            side.simdPosition = SIMD3(x, floor, 0)
            rack.addChildNode(side)
        }
        let front = box(width + 0.012, Self.rackWallHeight, Self.rackWallThickness, chamfer: 0.002, material: wood)
        front.simdPosition = SIMD3(0, floor, length / 2)
        rack.addChildNode(front)
        let back = box(width + 0.012, 0.15, 0.012, chamfer: 0.002, material: wood)
        back.simdPosition = SIMD3(0, 0.014, -length / 2)
        rack.addChildNode(back)
        for x in [-width / 2, width / 2] {
            let rail = node(SCNCylinder(radius: 0.004, height: CGFloat(length)), metal)
            rail.simdEulerAngles.x = .pi / 2
            rail.simdPosition = SIMD3(x, 0.118, 0)
            rack.addChildNode(rail)
        }

        let hotspot = SCNNode(geometry: SCNBox(width: CGFloat(width), height: 0.3, length: CGFloat(length), chamferRadius: 0))
        hotspot.simdPosition = SIMD3(0, 0.15, 0)
        hotspot.isHidden = true
        rack.addChildNode(hotspot)
        hotspotNodes[.rack] = hotspot
        let side = CGFloat(Self.rackSleeveSide)
        let frontRecord = SCNNode(geometry: SCNBox(width: side, height: side, length: 0.02, chamferRadius: 0))
        let lean = Self.rackLie(0)
        frontRecord.simdPosition = SIMD3(0, lean.y, lean.z)
            + SIMD3(0, cos(lean.angle), sin(lean.angle)) * Self.rackSleeveSide / 2
        frontRecord.simdEulerAngles.x = lean.angle
        frontRecord.isHidden = true
        rack.addChildNode(frontRecord)
        hotspotNodes[.rackRecord] = frontRecord
        machine.addChildNode(rack)
    }

    /// How the record `depth` from the front of the bin stands (0 at the front, less
    /// for the ones flipped past): where its bottom edge is along the bin (`z`) and
    /// above it (`y`), how far it's tipped forward (radians; back is less than 0), and
    /// whether it shows.
    ///
    /// Standing records stand on the floor. A flipped one lies over the front wall,
    /// resting on its top edge with its bottom edge lifted inside the bin, never through
    /// the wall (LYRE-1): the last flipped on top and most upright, those before it
    /// lower and flatter beneath.
    static func rackLie(_ depth: Float) -> (z: Float, y: Float, angle: Float, opacity: Float) {
        if depth >= 0 {
            // Standing one behind another, leaning back a little; only so many show.
            return (rackFrontZ - depth * 0.013, rackFloor, -0.14 - min(depth, 1) * 0.02,
                    depth > 9 ? max(0, 10 - depth) : 1)
        }
        let flipped = -depth
        let opacity: Float = flipped > 3 ? max(0, 4 - flipped) : 1
        let angle = min(flipped, 1) * 0.86 + (flipped - min(flipped, 1)) * 0.06
        // Where it touches the wall's top edge: just clear of it, each one before the
        // last a sleeve's thickness lower (no lower than the wall).
        let below = min(max(flipped - 1, 0), 3)
        let rest = rackWallTop + 0.004 + (3 - below) * 0.004
        // Its bottom edge, a little in front of the records standing.
        let footZ = rackFrontZ + 0.012
        let rise = (rackWallInside - footZ) / max(tan(angle), 0.01)
        let footY = max(rackFloor, rest - rise)
        // Partway over (the first flip), from standing on the floor to lying on the wall.
        let over = min(flipped, 1)
        return (rackFrontZ + (footZ - rackFrontZ) * over, rackFloor + (footY - rackFloor) * over, angle, opacity)
    }

    // MARK: Building Blocks

    private func box(_ width: Float, _ height: Float, _ length: Float, chamfer: Float = 0,
                     material: SCNMaterial) -> SCNNode {
        let box = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length),
                         chamferRadius: CGFloat(chamfer))
        box.chamferSegmentCount = 3
        box.firstMaterial = material
        let node = SCNNode(geometry: box)
        // Stood on its base, so it's placed by its bottom.
        node.simdPivot = simd_float4x4(translation: SIMD3(0, -height / 2, 0))
        return node
    }

    private func node(_ geometry: SCNGeometry, _ material: SCNMaterial) -> SCNNode {
        geometry.firstMaterial = material
        return SCNNode(geometry: geometry)
    }

    private func add(_ node: SCNNode, at position: SIMD3<Float>) {
        node.simdPosition = position
        machine.addChildNode(node)
    }

    private func addHotspot(_ spot: GramophoneHotspot, size: SIMD3<Float>, at center: SIMD3<Float>) {
        let node = SCNNode(geometry: SCNBox(width: CGFloat(size.x), height: CGFloat(size.y),
                                            length: CGFloat(size.z), chamferRadius: 0))
        node.simdPosition = center
        node.isHidden = true
        machine.addChildNode(node)
        hotspotNodes[spot] = node
    }

    // MARK: - What's Shown

    /// The record on the turntable, or none.
    func setRecord(_ record: RecordOnPlatter?) {
        let changed = record?.id != self.record?.id || record?.grooves != self.record?.grooves
        let labelChanged = record?.id != self.record?.id
        self.record = record
        if !isPutting { recordNode.isHidden = record == nil }
        guard changed else { return }
        if labelChanged { labelImage = nil }
        setRecordTexture()
        guard labelChanged, let record else { return }
        Task {
            let image = await RecordLabelArt.image(for: record.label)
            guard let image, self.record?.id == record.id, labelImage == nil else { return }
            setLabel(image)
        }
    }

    /// The picture on the record's label: the cover of what's playing.
    func setLabel(_ image: UIImage?) {
        guard let image, image !== labelImage else { return }
        labelImage = image
        setRecordTexture()
    }

    private func setRecordTexture() {
        guard let record else { return }
        recordFace.diffuse.contents = GramophoneTextures.record(record, labelImage: labelImage)
    }

    /// The record turning, at 33⅓.
    func setSpinning(_ spinning: Bool) {
        isSpinning = spinning
        if spinning {
            guard spinner.action(forKey: "spin") == nil else { return }
            spinner.runAction(.repeatForever(.rotateBy(x: 0, y: -2 * .pi, z: 0, duration: 1.8)), forKey: "spin")
        } else {
            spinner.removeAction(forKey: "spin")
        }
    }

    /// The tonearm at `angle` over the deck (as TonearmGeometry measures it), lifted
    /// off the record or not.
    func setArm(angle: Double, lifted: Bool, animated: Bool) {
        // A swing of the arm is drawn smoothly; its creep along the groove as the record
        // plays, a hair a tick, needn't be.
        if abs(angle - armAngle) > 0.01 || lifted != isArmLifted { boost(animated ? 0.5 : 0.25) }
        armAngle = angle
        isArmLifted = lifted
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.5 : 0
        armYaw.simdEulerAngles.y = -Float(angle)
        armLift.simdEulerAngles.z = lifted ? 0.07 : 0
        SCNTransaction.commit()
    }

    func setSwitch(on: Bool, animated: Bool = true) {
        isSwitchOn = on
        if animated { boost(0.22) }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.22 : 0
        switchLever.simdEulerAngles.z = on ? -0.6 : 0.6
        SCNTransaction.commit()
    }

    func setCrank(degrees: Double) {
        // Turned by the finger: drawn smoothly while it turns.
        if degrees != crankDegrees { boost(0.25) }
        crankDegrees = degrees
        crank.simdEulerAngles.x = Float(degrees * .pi / 180)
    }

    /// The drawer pulled out, or pushed back in.
    func setDrawer(open: Bool, animated: Bool = true) {
        isDrawerOpen = open
        if animated { boost(0.6) }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.6 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        drawer.simdPosition = SIMD3(0, 0.0775, 0.25 + (open ? Self.drawerTravel : 0))
        SCNTransaction.commit()
    }

    /// The covers on the records in the drawer, top first; the rest stay plain.
    func setDrawerStack(art: [UIImage?]) {
        stackArt = art
        let colors: [UIColor] = [UIColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 1), UIColor(red: 0.5, green: 0.12, blue: 0.1, alpha: 1),
                                 UIColor(red: 0.14, green: 0.2, blue: 0.32, alpha: 1)]
        for (depth, sleeve) in stackSleeves.enumerated() {
            guard let box = sleeve.geometry as? SCNBox else { continue }
            let paper = sleeve.geometry?.firstMaterial ?? Self.paper(colors[depth % colors.count])
            guard depth < art.count, let image = art[depth] else {
                box.materials = [paper]
                continue
            }
            let face = Self.paper(.white)
            face.diffuse.contents = image
            face.roughness.contents = 0.65
            // An SCNBox's faces: front, right, back, left, top, bottom.
            box.materials = [paper, paper, paper, paper, face, paper]
        }
    }

    /// Hides the records lying in the drawer while the crate is shown over them.
    func setDrawerStackHidden(_ hidden: Bool) {
        isDrawerStackHidden = hidden
        drawerStack.isHidden = hidden
    }

    /// Up Next, by its songs' ids, for the bin. The front record stays where it was,
    /// as near as the list allows.
    func setRackQueue(ids: [String]) {
        guard ids != rackIDs else { return }
        rackIDs = ids
        rackIndex = min(rackIndex, max(ids.count - 1, 0))
        rackSleeves.values.forEach { $0.removeFromParentNode() }
        rackSleeves = [:]
        rackPull = 0
        rackSlide = 0
        layOutRack(animated: false)
    }

    func hasRackArt(id: String) -> Bool { rackArt[id] != nil }

    /// A song's cover, for its record in the bin.
    func setRackArt(_ image: UIImage, id: String) {
        rackArt[id] = image
        for (index, sleeve) in rackSleeves where rackIDs.indices.contains(index) && rackIDs[index] == id {
            dress(sleeve, with: image)
        }
    }

    /// Flips through the bin to the record at `index`: the ones before it lean forward.
    func setRackIndex(_ index: Int, animated: Bool) {
        let index = min(max(index, 0), max(rackIDs.count - 1, 0))
        rackIndex = index
        rackPull = 0
        rackSlide = 0
        layOutRack(animated: animated)
    }

    /// A flip followed by a finger: toward the next record (up to 1), or the one
    /// before back up (down to -1).
    func setRackPull(_ pull: Float, animated: Bool = false) {
        rackPull = min(max(pull, -1), 1)
        layOutRack(animated: animated, duration: 0.3)
    }

    /// The front record pushed to the left (`slide` in metres), as far as the way to
    /// take it out shows.
    func setRackSlide(_ slide: Float, animated: Bool) {
        rackSlide = slide
        layOutRack(animated: animated, duration: 0.25)
    }

    /// Stands the bin's records where they go: each one's lie from its place behind
    /// the front, partway to the next place while a flip is under way.
    private func layOutRack(animated: Bool, duration: CFTimeInterval = 0.38) {
        guard !rackIDs.isEmpty else {
            rackSleeves.values.forEach { $0.removeFromParentNode() }
            rackSleeves = [:]
            return
        }
        let window = max(rackIndex - 5, 0)...min(rackIndex + 11, rackIDs.count - 1)
        for index in window where rackSleeves[index] == nil {
            let sleeve = makeRackSleeve(id: rackIDs[index])
            // New ones come in from where they were last out of sight, unseen.
            place(sleeve, depth: Float(index - rackIndex), slide: 0)
            sleeve.opacity = 0
            rack.addChildNode(sleeve)
            rackSleeves[index] = sleeve
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? duration : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        for (index, sleeve) in rackSleeves {
            let depth = Float(index - rackIndex) - rackPull
            place(sleeve, depth: depth, slide: index == rackIndex ? rackSlide : 0)
        }
        SCNTransaction.commit()
        for (index, sleeve) in rackSleeves where !window.contains(index) {
            rackSleeves[index] = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? duration : 0)) {
                sleeve.removeFromParentNode()
            }
        }
    }

    private func place(_ sleeve: SCNNode, depth: Float, slide: Float) {
        // Between two whole places, partway from one's lie to the other's.
        let low = floor(depth), t = depth - low
        let a = Self.rackLie(low), b = Self.rackLie(low + 1)
        sleeve.simdPosition = SIMD3(slide, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
        sleeve.simdEulerAngles.x = a.angle + (b.angle - a.angle) * t
        sleeve.opacity = CGFloat(a.opacity + (b.opacity - a.opacity) * t)
    }

    /// A record in its sleeve for the bin, standing on its bottom edge, which it tips
    /// forward on.
    private func makeRackSleeve(id: String) -> SCNNode {
        let side = Self.rackSleeveSide
        let sleeve = SCNNode()
        let paper = SCNNode(geometry: SCNBox(width: CGFloat(side), height: CGFloat(side), length: 0.004, chamferRadius: 0.001))
        paper.simdPosition = SIMD3(0, side / 2, 0)
        sleeve.addChildNode(paper)
        dress(sleeve, with: rackArt[id])
        return sleeve
    }

    private func dress(_ sleeve: SCNNode, with image: UIImage?) {
        guard let box = sleeve.childNodes.first?.geometry as? SCNBox else { return }
        let back = Self.paper(UIColor(red: 0.36, green: 0.28, blue: 0.2, alpha: 1))
        let face = Self.paper(UIColor(red: 0.62, green: 0.47, blue: 0.3, alpha: 1))
        if let image { face.diffuse.contents = image }
        face.roughness.contents = 0.6
        // A box's sides: front, right, back, left, top, bottom.
        box.materials = [face, back, back, back, back, back]
    }

    /// The speed knob turned to `rate`: upright for 1×, or for music, which always
    /// plays at its own speed.
    func setSpeed(rate: Float, isEnabled: Bool) {
        speedTurn = isEnabled ? -(rate - 1) * 1.6 : 0
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        speedKnob.simdEulerAngles.z = speedTurn
        SCNTransaction.commit()
    }

    func setPlate(title: String, subtitle: String, force: Bool = false) {
        guard force || plateText.0 != title || plateText.1 != subtitle else { return }
        plateText = (title, subtitle)
        plateCard.diffuse.contents = GramophoneTextures.plate(title: title, subtitle: subtitle, theme: theme)
    }

    /// Hides the record and the arm while the 2D turntable lies over them.
    func setTurntableHidden(_ hidden: Bool) {
        isTurntableHidden = hidden
        armYaw.isHidden = hidden
        spinner.isHidden = hidden
    }

    // MARK: - Putting a Record On

    /// The record on the platter lifted away, before another goes on.
    func liftRecordOff(animated: Bool) async {
        guard !recordNode.isHidden else { return }
        isPutting = true
        await animate(animated ? 0.3 : 0) { recordNode.opacity = 0 }
        recordNode.isHidden = true
        recordNode.opacity = 1
    }

    /// A record put on: its sleeve comes in over the front, the record slides out of
    /// the top of it and down onto the platter, the sleeve goes, and the arm lifts off
    /// its rest, swings over to `angle` and lowers the needle onto the record.
    func putRecord(kind: RecordKind, sleeveArt: UIImage?, armTo angle: Double, animated: Bool) async {
        isPutting = true
        recordNode.isHidden = true
        let r = Self.recordRadius
        let seat = spinner.simdPosition
        let sleeve = SCNNode(geometry: SCNBox(width: CGFloat(r * 2.08), height: 0.006, length: CGFloat(r * 2.08),
                                              chamferRadius: 0.002))
        let color: UIColor = switch kind {
        case .album: UIColor(white: 0.1, alpha: 1)
        case .homeRecording: UIColor(red: 0.62, green: 0.47, blue: 0.3, alpha: 1)
        case .transcription: UIColor(red: 0.12, green: 0.18, blue: 0.3, alpha: 1)
        }
        let edge = Self.paper(color)
        let cover = Self.paper(color)
        if let sleeveArt { cover.diffuse.contents = sleeveArt }
        sleeve.geometry?.materials = [edge, edge, edge, edge, cover, edge]
        let disc = recordNode.clone()
        disc.isHidden = false
        disc.opacity = 1

        // In its sleeve, coming in over the front of the machine.
        let hover = SIMD3<Float>(0, 0.11, 0)
        let start = seat + hover + SIMD3(0, 0, 0.75)
        let outside = seat + hover + SIMD3(0, 0, r * 2 + 0.03)
        sleeve.simdPosition = start
        disc.simdPosition = start - SIMD3(0, 0.003, 0)
        machine.addChildNode(sleeve)
        machine.addChildNode(disc)
        setArm(angle: Self.armGeometry.restAngle, lifted: false, animated: animated)

        await animate(animated ? 0.55 : 0) {
            sleeve.simdPosition = outside
            disc.simdPosition = outside - SIMD3(0, 0.003, 0)
        }
        // The record slides out of the sleeve's open end, over the platter.
        await animate(animated ? 0.6 : 0) { disc.simdPosition = seat + hover - SIMD3(0, 0.01, 0) }
        // The sleeve goes, and the record comes down onto the platter.
        await animate(animated ? 0.45 : 0) {
            sleeve.simdPosition = start
            sleeve.opacity = 0
            disc.simdPosition = seat
        }
        sleeve.removeFromParentNode()
        disc.removeFromParentNode()
        recordNode.isHidden = false
        isPutting = false

        // The arm: up, over, and down.
        await animate(animated ? 0.2 : 0) { armLift.simdEulerAngles.z = 0.09 }
        await animate(animated ? 0.65 : 0) { armYaw.simdEulerAngles.y = -Float(angle) }
        await animate(animated ? 0.3 : 0) { armLift.simdEulerAngles.z = 0 }
        armAngle = angle
        isArmLifted = false
    }

    /// Changes made over `duration` seconds, eased; returns when they're done.
    private func animate(_ duration: TimeInterval, _ changes: () -> Void) async {
        boost(duration)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        changes()
        SCNTransaction.commit()
        if duration > 0 { try? await Task.sleep(for: .seconds(duration)) }
    }

    // MARK: - The Camera

    /// The view's size and the room the player's own controls take at the top and the
    /// bottom, which the machine is framed clear of.
    func layout(size: CGSize, topInset: CGFloat, bottomInset: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        guard size != viewSize || insets.top != topInset || insets.bottom != bottomInset else { return }
        viewSize = size
        insets = (topInset, bottomInset)
        updatePoses()
    }

    /// Where the 2D turntable is, in window coordinates, for the camera to come down
    /// over its record.
    func setOverheadTurntable(frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        let (center, radius) = TurntableView.platter(in: frame.size)
        let windowCenter = CGPoint(x: frame.minX + center.x, y: frame.minY + center.y)
        let local = view.map { $0.convert(windowCenter, from: nil) } ?? windowCenter
        guard overheadRecord?.center != local || overheadRecord?.radius != radius else { return }
        overheadRecord = (local, radius)
        updatePoses()
    }

    private func updatePoses() {
        guard viewSize.width > 0 else { return }
        let top: Float = model == .horn ? deckY + 0.56 : deckY + 0.45
        // Square on, centred on the machine; the rack to the left runs off the edge.
        poses[.front] = GramophoneCameraPose.front(
            bounds: (SIMD3(-0.32, 0.02, -0.2), SIMD3(0.32, top, 0.27)),
            aspect: Float(viewSize.width / viewSize.height), fieldOfView: Self.fieldOfView,
            yaw: 0, pitch: 0.26, margin: 0.02,
            topInset: Float(insets.top / viewSize.height), bottomInset: Float(insets.bottom / viewSize.height),
            // Only with the bin taking the bottom half (iPhone Duo): the machine's room
            // is then all above the middle of the screen.
            fitsBand: insets.bottom > viewSize.height * 0.3)
        let recordCenter = SIMD3(Self.platterCenter.x, recordTopY, Self.platterCenter.y)
        let target = overheadRecord ?? (CGPoint(x: viewSize.width * 0.45, y: viewSize.height * 0.4), viewSize.width * 0.37)
        poses[.turntable] = GramophoneCameraPose.overhead(
            recordCenter: recordCenter, recordRadius: Self.recordRadius, screenCenter: target.center,
            screenRadius: target.radius, viewSize: viewSize, fieldOfView: Self.fieldOfView)
        // The drawer's inside filling the width of the screen, a little below the middle.
        let depth: Float = 0.42
        let drawerCenter = SIMD3<Float>(0, 0.062, 0.25 + Self.drawerTravel - 0.007 - depth / 2)
        poses[.drawer] = GramophoneCameraPose.overhead(
            recordCenter: drawerCenter, recordRadius: 0.21,
            screenCenter: CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.56),
            screenRadius: viewSize.width / 2, viewSize: viewSize, fieldOfView: Self.fieldOfView)
        // Round in front of the bin, a little from above, onto the record at its front.
        let yaw = Self.rackYaw, pitch: Float = 0.62
        let turn = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        let binTarget = Self.rackPosition + turn.act(SIMD3(0, 0.17, Self.rackFrontZ + 0.02))
        let back = SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        let tanH = tan(Self.fieldOfView * .pi / 360)
        let distance = (Self.rackSleeveSide / 2 + 0.035) / tanH
        poses[.rack] = GramophoneCameraPose(position: binTarget + back * distance, target: binTarget, up: SIMD3(0, 1, 0))
        if driver == nil { applyShot() }
    }

    /// How much of the horn shows from each shot: from straight above the record it
    /// would be in the way, so it fades as the camera rises past it.
    private static func hornOpacity(_ shot: GramophoneShot) -> Float {
        shot == .front || shot == .rack ? 1 : 0
    }

    /// The camera at its shot.
    private func applyShot() {
        guard let pose = poses[shot] else { return }
        cameraNode.simdPosition = pose.position
        cameraNode.simdOrientation = pose.orientation
        horn?.opacity = CGFloat(Self.hornOpacity(shot))
        if shot != .turntable { publishHotspots() }
    }

    /// Where the camera is now, as a pose to move from.
    private var currentPose: GramophoneCameraPose {
        if driver == nil, let pose = poses[shot] { return pose }
        let orientation = cameraNode.simdOrientation
        return GramophoneCameraPose(position: cameraNode.simdPosition,
                                    target: cameraNode.simdPosition + orientation.act(SIMD3(0, 0, -1)),
                                    up: orientation.act(SIMD3(0, 1, 0)))
    }

    /// Moves the camera to `target` over `duration` seconds. Returns false if another
    /// move took over first.
    @discardableResult
    func move(to target: GramophoneShot, duration: TimeInterval) async -> Bool {
        let start = currentPose
        let startHorn = Float(horn?.opacity ?? 1)
        driver?.cancel()
        driver = nil
        shot = target
        guard duration > 0, let end = poses[target] else {
            applyShot()
            return true
        }
        let path = GramophoneCameraPath(from: start, to: end)
        let endHorn = Self.hornOpacity(target)
        return await withCheckedContinuation { continuation in
            let driver = CameraDriver(duration: duration) { [weak self] progress in
                guard let self else { return }
                let t = Float(progress)
                let pose = path.pose(at: t)
                cameraNode.simdPosition = pose.position
                cameraNode.simdOrientation = pose.orientation
                horn?.opacity = CGFloat(startHorn + (endHorn - startHorn) * GramophoneMesh.smoothstep(0.3, 0.75, t))
            } completion: { [weak self] finished in
                if finished {
                    self?.driver = nil
                    self?.applyShot()
                }
                continuation.resume(returning: finished)
            }
            self.driver = driver
            boost(duration)
            driver.start()
        }
    }

    /// Once the frame with the camera where it is now has been drawn, so the view
    /// projects from where the camera is. A slow device may not have drawn it yet, so
    /// it's projected again a little later.
    private func publishHotspots() {
        for delay in [0.1, 0.4, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.shot != .turntable, self.driver == nil else { return }
                self.projectHotspots()
            }
        }
    }

    private func projectHotspots() {
        guard let view, let onHotspots else { return }
        var rects: [GramophoneHotspot: CGRect] = [:]
        for (spot, node) in hotspotNodes {
            // From the box's own size: a hidden node's bounding box is empty.
            guard let box = node.geometry as? SCNBox else { continue }
            let high = SCNVector3(Float(box.width) / 2, Float(box.height) / 2, Float(box.length) / 2)
            let low = SCNVector3(-high.x, -high.y, -high.z)
            var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
            for k in 0..<8 {
                let corner = SCNVector3(k & 1 == 0 ? low.x : high.x, k & 2 == 0 ? low.y : high.y, k & 4 == 0 ? low.z : high.z)
                let projected = view.projectPoint(node.convertPosition(corner, to: nil))
                minX = min(minX, CGFloat(projected.x)); maxX = max(maxX, CGFloat(projected.x))
                minY = min(minY, CGFloat(projected.y)); maxY = max(maxY, CGFloat(projected.y))
            }
            rects[spot] = view.convert(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), to: nil)
        }
        onHotspots(rects)
    }
}

// MARK: - Camera Driver

/// Runs a move once a frame, eased in and out.
private final class CameraDriver: NSObject {
    private let duration: CFTimeInterval
    private let step: (Double) -> Void
    private var completion: ((Bool) -> Void)?
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval?

    init(duration: CFTimeInterval, step: @escaping (Double) -> Void, completion: @escaping (Bool) -> Void) {
        self.duration = duration
        self.step = step
        self.completion = completion
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func cancel() { finish(false) }

    @objc private func tick(_ link: CADisplayLink) {
        let start = startTime ?? link.timestamp
        startTime = start
        let progress = min((link.timestamp - start) / max(duration, 0.001), 1)
        let eased = progress < 0.5 ? 4 * pow(progress, 3) : 1 - pow(-2 * progress + 2, 3) / 2
        step(eased)
        if progress >= 1 { finish(true) }
    }

    private func finish(_ finished: Bool) {
        link?.invalidate()
        link = nil
        completion?(finished)
        completion = nil
    }
}

private extension simd_float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(translation, 1)
    }
}

// MARK: - Stage View

/// The 3D machine, shown full screen behind the player's controls.
struct GramophoneStageView: UIViewRepresentable {
    let stage: GramophoneStage
    let topInset: CGFloat
    let bottomInset: CGFloat

    func makeUIView(context: Context) -> StageSCNView {
        let view = StageSCNView(frame: .zero, options: nil)
        stage.attach(view)
        view.onLayout = { [weak stage, weak view] size in
            guard let stage, let view else { return }
            stage.layout(size: size, topInset: view.topInset, bottomInset: view.bottomInset)
        }
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: StageSCNView, context: Context) {
        view.topInset = topInset
        view.bottomInset = bottomInset
        stage.layout(size: view.bounds.size, topInset: topInset, bottomInset: bottomInset)
    }

    final class StageSCNView: SCNView {
        var onLayout: ((CGSize) -> Void)?
        var topInset: CGFloat = 0
        var bottomInset: CGFloat = 0

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(bounds.size)
        }
    }
}
