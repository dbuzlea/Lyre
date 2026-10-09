//
//  GramophoneMeshes.swift
//  Lyre
//

import CoreGraphics
import SceneKit
import simd

// MARK: - Gramophone Meshes
//
// The 3D machine's shapes that SceneKit doesn't come with:
//
//   lathe   a part turned on a lathe: the platter, the columns, knobs, feet
//   disc    a flat disc with a picture laid across it: a record's face
//   horn    the horn, swept along a curving neck and opening into a fluted bell
//
// and the camera's path, from looking at the machine's front to looking straight down
// on the record.

nonisolated enum GramophoneMesh {

    /// A part turned on a lathe: `profile` is (radius, height) pairs from the bottom up,
    /// revolved about the y axis. Repeating a point makes a sharp edge there.
    static func lathe(_ profile: [SIMD2<Float>], segments: Int = 48) -> SCNGeometry {
        let rows = profile.count
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        for (i, point) in profile.enumerated() {
            // The outward normal, square to the profile here.
            var tangent = profile[min(i + 1, rows - 1)] - profile[max(i - 1, 0)]
            if simd_length(tangent) < 1e-7 { tangent = SIMD2(0, 1) }
            let normal = simd_normalize(SIMD2(tangent.y, -tangent.x))
            for j in 0...segments {
                let phi = Float(j) / Float(segments) * 2 * .pi
                positions.append(SIMD3(point.x * cos(phi), point.y, point.x * sin(phi)))
                normals.append(SIMD3(normal.x * cos(phi), normal.y, normal.x * sin(phi)))
                uvs.append(SIMD2(Float(j) / Float(segments), Float(i) / Float(max(rows - 1, 1))))
            }
        }
        var indices: [UInt32] = []
        let stride = UInt32(segments + 1)
        for i in 0..<UInt32(max(rows - 1, 0)) {
            for j in 0..<UInt32(segments) {
                let a = i * stride + j, b = a + stride, c = a + 1, d = b + 1
                indices += [a, b, c, b, d, c]
            }
        }
        return geometry(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }

    /// A flat disc facing up, with its picture laid flat across it: the picture's top
    /// toward -z, the back of the machine.
    static func disc(radius: Float, segments: Int = 96) -> SCNGeometry {
        var positions: [SIMD3<Float>] = [.zero]
        var uvs: [SIMD2<Float>] = [SIMD2(0.5, 0.5)]
        for j in 0...segments {
            let phi = Float(j) / Float(segments) * 2 * .pi
            positions.append(SIMD3(radius * cos(phi), 0, radius * sin(phi)))
            uvs.append(SIMD2(0.5 + 0.5 * cos(phi), 0.5 + 0.5 * sin(phi)))
        }
        var indices: [UInt32] = []
        for j in 0..<UInt32(segments) { indices += [0, j + 2, j + 1] }
        let normals = Array(repeating: SIMD3<Float>(0, 1, 0), count: positions.count)
        return geometry(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }

    /// The horn's outside and its inside, which shades darker toward the throat.
    struct Horn {
        let outer: SCNGeometry
        let inner: SCNGeometry
    }

    /// The horn: a tube swept along a curve through `spine` from the throat to the mouth,
    /// widening from `throat` to `mouth` radius and flaring hardest at the end, and
    /// fluted into `petals` panels that scallop the rim.
    static func horn(spine controlPoints: [SIMD3<Float>], throat: Float, mouth: Float,
                     petals: Int = 10, rings: Int = 72, segments: Int = 160,
                     thickness: Float = 0.0025) -> Horn {
        let spine = resample(catmullRom(controlPoints, samplesPerSpan: 40), count: rings)
        let frames = transportFrames(spine)

        // The rings, throat to mouth.
        var outer: [SIMD3<Float>] = []
        var radial: [SIMD3<Float>] = []
        var along: [Float] = []
        for (i, point) in spine.enumerated() {
            let s = Float(i) / Float(rings - 1)
            let radius = throat + (mouth - throat) * pow(s, 4)
            let flute = 0.07 * pow(s, 2.5)
            // The rim's scallops reach out past the seams between the panels.
            let lip = mouth * 0.035 * smoothstep(0.9, 1, s)
            let (tangent, normal, binormal) = frames[i]
            for j in 0...segments {
                let theta = Float(j) / Float(segments) * 2 * .pi
                let panel = petal(theta, count: petals)
                let direction = cos(theta) * normal + sin(theta) * binormal
                outer.append(point + direction * radius * (1 + flute * (panel - 0.6)) + tangent * lip * panel)
                radial.append(direction)
                along.append(s)
            }
        }
        let stride = segments + 1
        func index(_ i: Int, _ j: Int) -> Int { i * stride + j }

        // Normals across the surface, pointing out.
        var normals = [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: outer.count)
        for i in 0..<rings {
            for j in 0...segments {
                let around = outer[index(i, min(j + 1, segments))] - outer[index(i, max(j - 1, 0))]
                let lengthwise = outer[index(min(i + 1, rings - 1), j)] - outer[index(max(i - 1, 0), j)]
                var n = simd_cross(around, lengthwise)
                if simd_length(n) < 1e-9 { n = radial[index(i, j)] }
                n = simd_normalize(n)
                normals[index(i, j)] = simd_dot(n, radial[index(i, j)]) < 0 ? -n : n
            }
        }
        // The seam where the ring closes shares one normal, so it doesn't show.
        for i in 0..<rings {
            let shared = simd_normalize(normals[index(i, 0)] + normals[index(i, segments)])
            normals[index(i, 0)] = shared
            normals[index(i, segments)] = shared
        }

        // The outside, wound to face out.
        var outerIndices: [UInt32] = []
        for i in 0..<(rings - 1) {
            for j in 0..<segments {
                let a = index(i, j), b = index(i + 1, j), c = index(i, j + 1), d = index(i + 1, j + 1)
                let facesOut = simd_dot(simd_cross(outer[b] - outer[a], outer[c] - outer[a]), normals[a]) >= 0
                outerIndices += facesOut
                    ? [a, b, c, b, d, c].map(UInt32.init)
                    : [a, c, b, b, c, d].map(UInt32.init)
            }
        }
        var uvs = (0..<outer.count).map { k in SIMD2(Float(k % stride) / Float(segments), along[k]) }

        // The inside: the same surface a little in, facing the other way.
        let inner = zip(outer, normals).map { $0 - $1 * thickness }
        let innerNormals = normals.map { -$0 }
        let innerIndices = stridedTriangles(outerIndices).flatMap { [$0.0, $0.2, $0.1] }
        let shade = along.map { s -> SIMD4<Float> in
            let light = 0.1 + 0.9 * pow(s, 1.6)
            return SIMD4(light, light, light, 1)
        }

        // The rim, joining the outside to the inside at the mouth.
        var rimPositions = outer, rimNormals = normals
        var rimIndices = outerIndices
        let last = rings - 1
        let rimStart = rimPositions.count
        for j in 0...segments {
            rimPositions.append(outer[index(last, j)])
            rimPositions.append(inner[index(last, j)])
            let tangent = frames[last].0
            rimNormals.append(tangent)
            rimNormals.append(tangent)
            uvs.append(SIMD2(Float(j) / Float(segments), 1))
            uvs.append(SIMD2(Float(j) / Float(segments), 1))
        }
        for j in 0..<segments {
            let a = rimStart + j * 2, b = a + 1, c = a + 2, d = a + 3
            let facesOut = simd_dot(simd_cross(rimPositions[b] - rimPositions[a], rimPositions[c] - rimPositions[a]),
                                    frames[last].0) >= 0
            rimIndices += facesOut
                ? [a, b, c, b, d, c].map(UInt32.init)
                : [a, c, b, b, c, d].map(UInt32.init)
        }

        let innerUVs = Array(uvs.prefix(inner.count))
        return Horn(
            outer: geometry(positions: rimPositions, normals: rimNormals, uvs: uvs, indices: rimIndices),
            inner: geometry(positions: inner, normals: innerNormals, uvs: innerUVs, indices: innerIndices, colors: shade)
        )
    }

    /// A panel of the bell: 0 at the seams between panels, 1 across their middles.
    static func petal(_ theta: Float, count: Int) -> Float {
        // Rounded panels meeting in soft creases.
        pow(abs(sin(Float(count) * theta / 2)), 0.35)
    }

    // MARK: Curves

    /// A smooth curve through `points`.
    static func catmullRom(_ points: [SIMD3<Float>], samplesPerSpan: Int) -> [SIMD3<Float>] {
        guard points.count > 1 else { return points }
        var curve: [SIMD3<Float>] = []
        for span in 0..<(points.count - 1) {
            let p0 = points[max(span - 1, 0)], p1 = points[span]
            let p2 = points[span + 1], p3 = points[min(span + 2, points.count - 1)]
            for step in 0..<samplesPerSpan {
                let t = Float(step) / Float(samplesPerSpan)
                let t2 = t * t, t3 = t2 * t
                let a = 2 * p1
                let b = (p2 - p0) * t
                let c = (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                let d = (3 * p1 - p0 - 3 * p2 + p3) * t3
                curve.append(0.5 * (a + b + c + d))
            }
        }
        curve.append(points[points.count - 1])
        return curve
    }

    /// `count` points evenly spaced along `curve`.
    static func resample(_ curve: [SIMD3<Float>], count: Int) -> [SIMD3<Float>] {
        guard curve.count > 1, count > 1 else { return curve }
        var lengths: [Float] = [0]
        for k in 1..<curve.count { lengths.append(lengths[k - 1] + simd_distance(curve[k], curve[k - 1])) }
        let total = lengths[lengths.count - 1]
        var result: [SIMD3<Float>] = []
        var k = 1
        for n in 0..<count {
            let target = total * Float(n) / Float(count - 1)
            while k < curve.count - 1 && lengths[k] < target { k += 1 }
            let span = max(lengths[k] - lengths[k - 1], 1e-9)
            let t = min(max((target - lengths[k - 1]) / span, 0), 1)
            result.append(simd_mix(curve[k - 1], curve[k], SIMD3(repeating: t)))
        }
        return result
    }

    /// A frame at each point of a curve (along it, and two across), turning no more
    /// than the curve does, so a tube swept along it doesn't twist.
    static func transportFrames(_ curve: [SIMD3<Float>]) -> [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] {
        guard curve.count > 1 else { return [] }
        var frames: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        var normal = SIMD3<Float>(0, 0, 0)
        for k in 0..<curve.count {
            let tangent = simd_normalize(curve[min(k + 1, curve.count - 1)] - curve[max(k - 1, 0)])
            if k == 0 {
                let seed: SIMD3<Float> = abs(tangent.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1)
                normal = simd_normalize(simd_cross(simd_cross(tangent, seed), tangent))
            } else {
                normal = simd_normalize(normal - simd_dot(normal, tangent) * tangent)
            }
            frames.append((tangent, normal, simd_cross(tangent, normal)))
        }
        return frames
    }

    static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: Building Geometry

    private static func stridedTriangles(_ indices: [UInt32]) -> [(UInt32, UInt32, UInt32)] {
        Swift.stride(from: 0, to: indices.count - 2, by: 3).map { (indices[$0], indices[$0 + 1], indices[$0 + 2]) }
    }

    static func geometry(positions: [SIMD3<Float>], normals: [SIMD3<Float>], uvs: [SIMD2<Float>],
                         indices: [UInt32], colors: [SIMD4<Float>]? = nil) -> SCNGeometry {
        var sources = [
            SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) }),
            SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) }),
            SCNGeometrySource(textureCoordinates: uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }),
        ]
        if let colors {
            let data = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            sources.append(SCNGeometrySource(data: data, semantic: .color, vectorCount: colors.count,
                                             usesFloatComponents: true, componentsPerVector: 4,
                                             bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                             dataStride: MemoryLayout<SIMD4<Float>>.stride))
        }
        return SCNGeometry(sources: sources, elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
}

// MARK: - Camera Path

/// Where the camera is and what it looks at.
nonisolated struct GramophoneCameraPose: Equatable {
    var position: SIMD3<Float>
    var target: SIMD3<Float>
    /// Which way is up on screen.
    var up: SIMD3<Float>

    var orientation: simd_quatf { Self.orientation(from: position, toward: target, up: up) }

    static func orientation(from position: SIMD3<Float>, toward target: SIMD3<Float>,
                            up: SIMD3<Float>) -> simd_quatf {
        let forward = simd_normalize(target - position)
        var right = simd_cross(forward, up)
        if simd_length(right) < 1e-5 { right = SIMD3(1, 0, 0) }
        right = simd_normalize(right)
        let trueUp = simd_cross(right, forward)
        // A camera looks down its -z, with +y up.
        return simd_quatf(simd_float3x3(columns: (right, trueUp, -forward)))
    }

    /// The camera straight above the record, at the height and offset that puts the
    /// record at `screenCenter` with `screenRadius`, in a view `viewSize` points big.
    /// With the camera looking straight down, the record's face is square to it, so
    /// it's a true circle wherever it lands: the overhead turntable drawn in 2D can lie
    /// exactly over it.
    static func overhead(recordCenter: SIMD3<Float>, recordRadius: Float, screenCenter: CGPoint,
                         screenRadius: CGFloat, viewSize: CGSize, fieldOfView degrees: Float) -> GramophoneCameraPose {
        let tanHalf = tan(degrees * .pi / 360)
        let height = Float(viewSize.width) * recordRadius / (2 * Float(screenRadius) * tanHalf)
        let scale = Float(screenRadius) / recordRadius
        let x = recordCenter.x - Float(screenCenter.x - viewSize.width / 2) / scale
        let z = recordCenter.z - Float(screenCenter.y - viewSize.height / 2) / scale
        return GramophoneCameraPose(position: SIMD3(x, recordCenter.y + height, z),
                                    target: SIMD3(x, recordCenter.y, z), up: SIMD3(0, 0, -1))
    }

    /// The camera in front of the machine, a little above and to the right, as far
    /// back as it takes to see all of `bounds` with the given margins (fractions of the
    /// view's half-height and half-width).
    static func front(bounds: (min: SIMD3<Float>, max: SIMD3<Float>), aspect: Float, fieldOfView degrees: Float,
                      yaw: Float, pitch: Float, margin: Float = 0.06,
                      topInset: Float = 0, bottomInset: Float = 0) -> GramophoneCameraPose {
        let tanH = tan(degrees * .pi / 360)
        let tanV = tanH / max(aspect, 0.1)
        // Toward the camera from what it looks at.
        let back = simd_normalize(SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)))
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(worldUp, back))
        let up = simd_cross(back, right)
        let corners = (0..<8).map { k in
            SIMD3(k & 1 == 0 ? bounds.min.x : bounds.max.x,
                  k & 2 == 0 ? bounds.min.y : bounds.max.y,
                  k & 4 == 0 ? bounds.min.z : bounds.max.z)
        }
        var target = (bounds.min + bounds.max) / 2
        var distance: Float = 1

        // Where the corners land on screen, from -1 to 1 across and up.
        func extent(_ distance: Float, _ target: SIMD3<Float>) -> (x: Float, low: Float, high: Float) {
            var x: Float = 0, low: Float = .infinity, high: Float = -.infinity
            for corner in corners {
                let offset = corner - target
                let depth = distance - simd_dot(offset, back)
                let sx = simd_dot(offset, right) / (depth * tanH)
                let sy = simd_dot(offset, up) / (depth * tanV)
                x = max(x, abs(sx)); low = min(low, sy); high = max(high, sy)
            }
            return (x, low, high)
        }

        let maxHigh = 1 - margin - topInset * 2, minLow = -1 + margin + bottomInset * 2
        for _ in 0..<3 {
            // As close as it can be with everything in view…
            var near: Float = 0.2, far: Float = 20
            for _ in 0..<40 {
                let mid = (near + far) / 2
                let e = extent(mid, target)
                if e.x <= 1 - margin && e.high <= maxHigh && e.low >= minLow { far = mid } else { near = mid }
            }
            distance = far
            // …then centred between the insets.
            let e = extent(distance, target)
            let shift = ((e.high + e.low) - (maxHigh + minLow)) / 2
            target += up * shift * distance * tanV
        }
        return GramophoneCameraPose(position: target + back * distance, target: target, up: worldUp)
    }
}

/// The camera's way from one shot to another: rising a little on the way, its look
/// swinging from what it looked at to what it's going to, and turning over as it comes
/// to look straight down.
nonisolated struct GramophoneCameraPath {
    let from: GramophoneCameraPose
    let to: GramophoneCameraPose

    /// Halfway, and a little higher, so the camera rises over the front edge of the
    /// machine rather than going through it.
    var via: SIMD3<Float> {
        (from.position + to.position) / 2 + SIMD3(0, 0.12, 0)
    }

    /// The pose a fraction `t` of the way.
    func pose(at t: Float) -> (position: SIMD3<Float>, orientation: simd_quatf) {
        let t = min(max(t, 0), 1)
        if t >= 1 { return (to.position, to.orientation) }
        let u = 1 - t
        let position = u * u * from.position + 2 * u * t * via + t * t * to.position
        let look = GramophoneMesh.smoothstep(0, 0.85, t)
        let target = simd_mix(from.target, to.target, SIMD3(repeating: look))
        let turn = GramophoneMesh.smoothstep(0.25, 1, t)
        var up = simd_mix(from.up, to.up, SIMD3(repeating: turn))
        if simd_length(up) < 1e-4 { up = to.up }
        return (position, GramophoneCameraPose.orientation(from: position, toward: target, up: simd_normalize(up)))
    }
}
