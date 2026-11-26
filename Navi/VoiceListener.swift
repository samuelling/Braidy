import AVFoundation
import SoundAnalysis

/// Listens through the microphone for the game's own voice acting.
///
/// Apple's built-in sound classifier (SoundAnalysis, ~300 everyday sounds) scores each ~1 s window
/// of audio, hopping every ~0.25 s. Navi watches the speech-like categories. A voiced cutscene line
/// gives seconds of sustained speech; an NPC's grunt or "Hmm!" gives one or two windows. So "the game
/// is talking" means speech in at least ~0.75 s worth of windows, not a single hit.
///
/// Navi's own voice is heard by the same microphone, so results are ignored while Navi is speaking
/// and for a moment after (the classifier window still contains the tail of Navi's line).
final class VoiceListener: NSObject, ObservableObject {
    /// Speech heard just now (drives the on-screen indicator).
    @Published private(set) var gameTalking = false
    /// Latest speech confidence, 0–1, for the meter in Settings.
    @Published private(set) var level: Double = 0
    /// nil until started; false if the mic or classifier is unavailable.
    @Published private(set) var available: Bool?

    /// Confidence a window needs to count as speech.
    var threshold: Double = 0.5

    private let engine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "navi.sound")
    private var hits: [(time: Date, confidence: Double)] = []
    private var selfSpeaking = false
    private var ignoreUntil = Date.distantPast
    private var configObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    var isRunning: Bool { engine.isRunning && available == true }

    static func isSpeech(_ label: String) -> Bool {
        label.contains("speech") || label.contains("conversation") || label.contains("narration")
    }

    // MARK: Start / stop

    func start() {
        AVAudioApplication.requestRecordPermission { ok in
            DispatchQueue.main.async {
                if ok { self.begin() } else { self.available = false }
            }
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if analyzer != nil { engine.inputNode.removeTap(onBus: 0) }
        analyzer?.removeAllRequests()
        analyzer = nil
        hits.removeAll()
        gameTalking = false
        level = 0
    }

    private func begin() {
        guard !engine.isRunning else { return }
        observeAudioChanges()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { available = false; return }

        let analyzer = SNAudioStreamAnalyzer(format: format)
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.overlapFactor = 0.75
            try analyzer.add(request, withObserver: self)
        } catch {
            available = false
            return
        }
        self.analyzer = analyzer
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, when in
            self?.analysisQueue.async { analyzer.analyze(buffer, atAudioFramePosition: when.sampleTime) }
        }
        do {
            engine.prepare()
            try engine.start()
            available = true
        } catch {
            input.removeTap(onBus: 0)
            available = false
        }
    }

    /// Route changes (headphones, AirPlay) and interruptions stop the engine; start it again.
    private func observeAudioChanges() {
        guard configObserver == nil else { return }
        let nc = NotificationCenter.default
        configObserver = nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                        queue: .main) { [weak self] _ in self?.restart() }
        interruptionObserver = nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                              queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.ended.rawValue { self?.restart() }
        }
    }

    func restart() {
        guard available == true || analyzer != nil else { return }
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.begin() }
    }

    // MARK: Navi's own voice

    func setSelfSpeaking(_ speaking: Bool) {
        selfSpeaking = speaking
        // The classifier window is ~1 s, so it keeps hearing Navi briefly after it stops.
        if !speaking { ignoreUntil = Date().addingTimeInterval(1.1) }
    }

    // MARK: Queries

    /// Did the game speak for at least ~0.75 s since `since`?
    func gameTalked(since: Date) -> Bool {
        hits.filter { $0.time >= since && $0.confidence >= threshold }.count >= 3
    }

    private func record(_ confidence: Double) {
        let now = Date()
        level = confidence
        let ignoring = selfSpeaking || now < ignoreUntil
        hits.append((now, ignoring ? 0 : confidence))
        hits.removeAll { now.timeIntervalSince($0.time) > 15 }
        let recent = hits.filter { now.timeIntervalSince($0.time) <= 1.2 && $0.confidence >= threshold }
        let talking = recent.count >= 2
        if talking != gameTalking { gameTalking = talking }
    }
}

extension VoiceListener: SNResultsObserving {
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        let speech = r.classifications.filter { Self.isSpeech($0.identifier) }.map(\.confidence).max() ?? 0
        DispatchQueue.main.async { self.record(speech) }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        DispatchQueue.main.async { self.available = false }
    }

    func requestDidComplete(_ request: SNRequest) {}
}
