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

    var body: some View {
        GeometryReader { geo in
            let frame = AVMakeRect(aspectRatio: camera.imageSize, insideRect: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                CameraPreview(camera: camera)
                    .frame(width: geo.size.width, height: geo.size.height)
                ForEach(Array(camera.rows.enumerated()), id: \.offset) { _, row in
                    let r = Self.place(row.box, in: frame)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.cyan.opacity(0.85), lineWidth: 2)
                        .frame(width: r.width + 6, height: r.height + 6)
                        .position(x: r.midX, y: r.midY)
                        .allowsHitTesting(false)
                }
                RegionBox(region: $region, frame: frame, editing: editing)
            }
        }
    }

    static func place(_ n: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + n.minX * frame.width, y: frame.minY + n.minY * frame.height,
               width: n.width * frame.width, height: n.height * frame.height)
    }
}

/// The area Braidy reads. Drag to move; drag the yellow dot to resize.
struct RegionBox: View {
    @Binding var region: CGRect
    let frame: CGRect
    let editing: Bool
    @State private var start: CGRect?

    var body: some View {
        let r = CameraStage.place(region, in: frame)
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.yellow.opacity(editing ? 0.12 : 0.001))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(editing ? Color.yellow : Color.white.opacity(0.6),
                                      style: StrokeStyle(lineWidth: editing ? 4 : 2, dash: editing ? [] : [10, 8]))
                )
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .gesture(move)
                .allowsHitTesting(editing)
            if editing {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 44, height: 44)
                    .shadow(radius: 4)
                    .position(x: r.maxX, y: r.maxY)
                    .gesture(resize)
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
                n.size.width = min(max(s.width + v.translation.width / max(frame.width, 1), 0.1), 1 - s.minX)
                n.size.height = min(max(s.height + v.translation.height / max(frame.height, 1), 0.06), 1 - s.minY)
                region = n
            }
            .onEnded { _ in start = nil }
    }
}
