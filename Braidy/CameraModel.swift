import AVFoundation
import CoreImage
import ImageIO
import UIKit
import Vision

/// Back camera → on-device text recognition (Vision) inside the reading box.
final class CameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var authorized: Bool? = nil
    /// Size of the upright camera image, used to map the reading box onto the preview.
    @Published var imageSize = CGSize(width: 16, height: 9)
    @Published var rows: [TextRow] = []
    @Published var maxZoom: CGFloat = 1
    var zoom: CGFloat = 1 { didSet { applyZoom() } }

    /// Called on the main thread with each analyzed frame's rows.
    var onFrame: (([TextRow]) -> Void)?

    /// Words Vision should trust even though they aren't English.
    var customWords: [String] = [] {
        didSet { let words = customWords; videoQueue.async { self.request.customWords = words } }
    }

    private let videoQueue = DispatchQueue(label: "braidy.video")
    private let output = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservers: [NSKeyValueObservation] = []
    private let ciContext = CIContext()

    private let lock = NSLock()
    private var _region = CGRect(x: 0.06, y: 0.55, width: 0.88, height: 0.4)
    private var _listening = true
    private var _snapshot: ((Data?) -> Void)?
    private var lastAnalysis = Date.distantPast

    private lazy var request: VNRecognizeTextRequest = {
        let r = VNRecognizeTextRequest()
        r.recognitionLevel = .accurate
        r.recognitionLanguages = ["en-US"]
        r.usesLanguageCorrection = true
        r.customWords = Self.commonWords
        return r
    }()

    /// Words from popular kids' games that OCR's English correction would otherwise "fix".
    /// Each game adds its own (character names and vocabulary from Claude).
    static let commonWords = ["Pokémon", "Pokemon", "Pikachu", "Eevee", "Mario", "Luigi", "Bowser", "Yoshi",
                            "Toad", "Kirby", "Hyrule", "Zelda", "Link", "Zonai", "Sheikah", "Gerudo", "Goron", "Zora", "Rito",
                            "Korok", "Koroks", "Purah", "Robbie", "Josha", "Impa", "Paya", "Sidon", "Riju",
                            "Tulin", "Yunobo", "Rauru", "Mineru", "Sonia", "Ganondorf", "Ganon", "Kakariko",
                            "Hateno", "Lurelin", "Tarrey", "Bokoblin", "Moblin", "Lizalfos", "Lynel", "Hinox",
                            "Rupee", "Rupees", "Tri", "Pokémon", "Pokemon"]

    // MARK: Thread-safe settings read on the video queue

    func setRegion(_ r: CGRect) { lock.lock(); _region = r; lock.unlock() }
    func setListening(_ on: Bool) { lock.lock(); _listening = on; lock.unlock() }
    private var region: CGRect { lock.lock(); defer { lock.unlock() }; return _region }
    private var listening: Bool { lock.lock(); defer { lock.unlock() }; return _listening }

    /// Grab the next camera frame as a JPEG (for asking Claude which game this is).
    func snapshot(_ completion: @escaping (Data?) -> Void) {
        lock.lock(); _snapshot = completion; lock.unlock()
    }

    // MARK: Setup

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    if ok { self.configure() } else { self.authorized = false }
                }
            }
        default:
            authorized = false
        }
    }

    private func configure() {
        authorized = true
        if device != nil {
            videoQueue.async { if !self.session.isRunning { self.session.startRunning() } }
            return
        }
        videoQueue.async {
            self.session.beginConfiguration()
            // Plenty of pixels so text stays legible from across the room.
            if self.session.canSetSessionPreset(.hd1920x1080) { self.session.sessionPreset = .hd1920x1080 }
            guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: dev),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.output.alwaysDiscardsLateVideoFrames = true
            self.output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            self.output.setSampleBufferDelegate(self, queue: self.videoQueue)
            if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
            self.session.commitConfiguration()

            let maxZ = min(dev.maxAvailableVideoZoomFactor, 6)
            DispatchQueue.main.async {
                self.device = dev
                self.maxZoom = maxZ
                self.applyZoom()
                self.setUpRotation()
            }
            self.session.startRunning()
        }
    }

    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        setUpRotation()
    }

    /// Keep the preview and the analyzed frames upright however the iPad is propped.
    private func setUpRotation() {
        guard rotationCoordinator == nil, let dev = device, let layer = previewLayer else { return }
        let rc = AVCaptureDevice.RotationCoordinator(device: dev, previewLayer: layer)
        rotationCoordinator = rc
        rotationObservers = [
            rc.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.applyRotation() }
            },
            rc.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.applyRotation() }
            },
        ]
        applyRotation()
    }

    private func applyRotation() {
        guard let rc = rotationCoordinator else { return }
        let preview = rc.videoRotationAngleForHorizonLevelPreview
        if let c = previewLayer?.connection, c.isVideoRotationAngleSupported(preview) {
            c.videoRotationAngle = preview
        }
        let capture = rc.videoRotationAngleForHorizonLevelCapture
        videoQueue.async {
            if let c = self.output.connection(with: .video), c.isVideoRotationAngleSupported(capture) {
                c.videoRotationAngle = capture
            }
        }
    }

    private func applyZoom() {
        guard let dev = device else { return }
        let z = max(1, min(zoom, dev.maxAvailableVideoZoomFactor))
        videoQueue.async {
            do {
                try dev.lockForConfiguration()
                dev.videoZoomFactor = z
                dev.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: Row assembly

    /// Put recognized fragments into reading order.
    ///
    /// 1. Lines: fragments at the same height that sit close together horizontally. (A choice at the
    ///    same height as a dialogue line, but off to the side, stays separate.)
    /// 2. Blocks: lines stacked closely with overlapping horizontal extent, such as a dialogue box with
    ///    its name label, or a list of choices.
    /// 3. Blocks are read left to right (top to bottom when they start at about the same x), and
    ///    each block top to bottom.
    static func assemble(_ items: [TextRow]) -> [TextRow] {
        var lines: [TextRow] = []
        for item in items.sorted(by: { $0.box.minX < $1.box.minX }) {
            if let i = lines.firstIndex(where: { line in
                abs(line.box.midY - item.box.midY) < min(line.box.height, item.box.height) * 0.5
                    && item.box.minX - line.box.maxX < max(line.box.height, item.box.height) * 2
            }) {
                lines[i].text += " " + item.text
                lines[i].box = lines[i].box.union(item.box)
            } else {
                lines.append(item)
            }
        }

        var blocks: [[TextRow]] = []
        for line in lines.sorted(by: { $0.box.minY < $1.box.minY }) {
            if let b = blocks.firstIndex(where: { block in
                let last = block[block.count - 1]
                let overlap = min(last.box.maxX, line.box.maxX) - max(last.box.minX, line.box.minX)
                let gap = line.box.minY - last.box.maxY
                return overlap > min(last.box.width, line.box.width) * 0.3
                    && gap < max(last.box.height, line.box.height) * 1.6
            }) {
                blocks[b].append(line)
            } else {
                blocks.append([line])
            }
        }

        // Bucket left edges (3% of the width) so blocks starting at about the same x sort by height.
        func key(_ block: [TextRow]) -> (Int, CGFloat) {
            let minX = block.map(\.box.minX).min() ?? 0
            return (Int(minX / 0.03), block[0].box.minY)
        }
        let ordered = blocks.sorted { key($0) < key($1) }
        var out: [TextRow] = []
        for (i, block) in ordered.enumerated() {
            for var line in block {
                line.block = i
                out.append(line)
            }
        }
        return out
    }
}

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lock.lock(); let snap = _snapshot; _snapshot = nil; lock.unlock()
        if let snap {
            let jpeg = makeJPEG(pixels)
            DispatchQueue.main.async { snap(jpeg) }
        }

        guard listening else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAnalysis) >= 0.12 else { return }
        lastAnalysis = now

        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        // Reading box is top-left origin; Vision wants bottom-left.
        let r = region
        let roi = CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !roi.isNull, roi.width > 0.02, roi.height > 0.02 else { return }
        request.regionOfInterest = roi

        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up, options: [:])
        try? handler.perform([request])

        var items: [TextRow] = []
        for obs in request.results ?? [] {
            guard let best = obs.topCandidates(1).first, best.confidence >= 0.3 else { continue }
            let s = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            guard letters >= 2 else { continue }
            // Boxes come back relative to the region of interest.
            let b = obs.boundingBox
            let full = CGRect(x: roi.minX + b.minX * roi.width, y: roi.minY + b.minY * roi.height,
                              width: b.width * roi.width, height: b.height * roi.height)
            items.append(TextRow(text: s, box: CGRect(x: full.minX, y: 1 - full.maxY,
                                                     width: full.width, height: full.height)))
        }
        let rows = Self.assemble(items)
        let size = CGSize(width: width, height: height)
        DispatchQueue.main.async {
            if self.imageSize != size { self.imageSize = size }
            if self.rows != rows { self.rows = rows }
            self.onFrame?(rows)
        }
    }

    private func makeJPEG(_ pixels: CVPixelBuffer) -> Data? {
        var image = CIImage(cvPixelBuffer: pixels)
        let longest = max(image.extent.width, image.extent.height)
        if longest > 1568 {
            let s = 1568 / longest
            image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return ciContext.jpegRepresentation(of: image, colorSpace: space, options: [quality: 0.7])
    }
}
