import AVFoundation
import SwiftUI

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let camera: CameraModel

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.previewLayer.session = camera.session
        // Aspect-fit, so the reading box maps straight onto the image.
        v.previewLayer.videoGravity = .resizeAspect
        camera.attach(v.previewLayer)
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// The camera picture with the reading box and the text Braidy can see.
struct CameraStage: View {
    @ObservedObject var camera: CameraModel
    @Binding var region: CGRect
    var editing: Bool
    @Binding var ignoreZones: [CGRect]
    /// Tapping text while editing turns it into an ignore zone.
    var ignoreText: ((CGRect) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let frame = AVMakeRect(aspectRatio: camera.imageSize, insideRect: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                CameraPreview(camera: camera)
                    .frame(width: geo.size.width, height: geo.size.height)
                RegionBox(region: $region, frame: frame, editing: editing)
                ForEach(ignoreZones.indices, id: \.self) { i in
                    RegionBox(region: Binding(get: { i < ignoreZones.count ? ignoreZones[i] : .zero },
                                              set: { if i < ignoreZones.count { ignoreZones[i] = $0 } }),
                              frame: frame, editing: editing, color: Theme.pink, label: "IGNORE",
                              minSize: CGSize(width: 0.03, height: 0.03),
                              onDelete: { if i < ignoreZones.count { ignoreZones.remove(at: i) } })
                }
                // What Braidy can read right now. While editing, tap any of it to ignore it.
                ForEach(Array(camera.rows.enumerated()), id: \.offset) { _, row in
                    let r = Self.place(row.box, in: frame)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.cyan.opacity(0.85), lineWidth: editing ? 3 : 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.cyan.opacity(editing ? 0.15 : 0)))
                        .frame(width: r.width + 6, height: r.height + 6)
                        .contentShape(Rectangle())
                        .onTapGesture { ignoreText?(row.box); Theme.tap() }
                        .position(x: r.midX, y: r.midY)
                        .allowsHitTesting(editing && ignoreText != nil)
                }
            }
        }
    }

    static func place(_ n: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + n.minX * frame.width, y: frame.minY + n.minY * frame.height,
               width: n.width * frame.width, height: n.height * frame.height)
    }
}

/// A box on the camera picture: the reading box (yellow) or an ignore zone (pink).
/// Drag to move; drag the dot to resize; the ✕ removes an ignore zone.
struct RegionBox: View {
    @Binding var region: CGRect
    let frame: CGRect
    let editing: Bool
    var color: Color = .yellow
    var label: String? = nil
    var minSize = CGSize(width: 0.1, height: 0.06)
    var onDelete: (() -> Void)? = nil
    @State private var start: CGRect?

    var body: some View {
        let r = CameraStage.place(region, in: frame)
        let isZone = onDelete != nil
        ZStack {
            RoundedRectangle(cornerRadius: isZone ? 8 : 14)
                .fill(color.opacity(editing ? 0.14 : (isZone ? 0.1 : 0.001)))
                .overlay(
                    RoundedRectangle(cornerRadius: isZone ? 8 : 14)
                        .strokeBorder(editing ? color : (isZone ? color.opacity(0.6) : Color.white.opacity(0.6)),
                                      style: StrokeStyle(lineWidth: editing ? 4 : 2, dash: editing ? [] : [10, 8]))
                )
                .overlay(alignment: .topLeading) {
                    if let label, editing || r.height > 30 {
                        Text(label).font(Theme.title(11)).tracking(1).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(color))
                            .padding(4)
                    }
                }
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .gesture(move)
                .allowsHitTesting(editing)
            if editing {
                Circle()
                    .fill(color)
                    .frame(width: isZone ? 34 : 44, height: isZone ? 34 : 44)
                    .shadow(radius: 4)
                    .position(x: r.maxX, y: r.maxY)
                    .gesture(resize)
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.night))
                            .overlay(Circle().strokeBorder(color, lineWidth: 2))
                    }
                    .position(x: r.maxX, y: r.minY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var move: some Gesture {
        DragGesture()
            .onChanged { v in
                let s = start ?? region
                if start == nil { start = region }
                var n = s
                n.origin.x = s.minX + v.translation.width / max(frame.width, 1)
                n.origin.y = s.minY + v.translation.height / max(frame.height, 1)
                n.origin.x = min(max(n.origin.x, 0), 1 - n.width)
                n.origin.y = min(max(n.origin.y, 0), 1 - n.height)
                region = n
            }
            .onEnded { _ in start = nil }
    }

    private var resize: some Gesture {
        DragGesture()
            .onChanged { v in
                let s = start ?? region
                if start == nil { start = region }
                var n = s
                n.size.width = min(max(s.width + v.translation.width / max(frame.width, 1), minSize.width), 1 - s.minX)
                n.size.height = min(max(s.height + v.translation.height / max(frame.height, 1), minSize.height), 1 - s.minY)
                region = n
            }
            .onEnded { _ in start = nil }
    }
}
