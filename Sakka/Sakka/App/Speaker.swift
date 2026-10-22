import AVFoundation

/// The Arabic voice of both games: the best-quality Arabic voice on the device (ar-KW first among equals),
/// heard with the Silent switch on, lowering music only while it speaks. A new line stops the one before it.
/// With no Arabic voice on the device, a short two-note chime stands in. The home page's sound setting mutes both.
///
/// The audio session is switched on and off on its own queue (those calls wait for the hardware and would stall
/// the motion on screen), and a line is spoken once the session is on. Music comes back up as soon as nothing is
/// being said or waiting to be said.
final class Speaker: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private let isOn: @MainActor () -> Bool
    private var voice: AVSpeechSynthesisVoice?
    private var prepared = false
    /// The voice list being read in the background.
    private var loading = false
    /// The voices changed while the list was being read: read it once more when that read is done.
    private var readAgain = false
    /// Goes up with every line and every stop, so a session that comes on late never speaks an old line.
    private var generation = 0
    /// A line (or the chime) waiting for the session to come on.
    private var waiting = false
    /// The line being spoken, until the synthesizer says it finished or was cut. Held, and compared as an object,
    /// so a late word about an old line can never be taken for the new one.
    private var current: AVSpeechUtterance?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var chimeBuffer: AVAudioPCMBuffer?
    private var chimeRelease: Task<Void, Never>?
    private var voicesObserver: (any NSObjectProtocol)?

    nonisolated private static let preference = ["ar-kw", "ar-sa", "ar-ae", "ar-qa", "ar-bh", "ar-om", "ar-001"]

    init(isOn: @escaping @MainActor () -> Bool) {
        self.isOn = isOn
        super.init()
        synthesizer.delegate = self
        // A voice downloaded in Settings while the app is open is used from the next line on.
        voicesObserver = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.voicesChanged() }
        }
    }

    private func voicesChanged() {
        if loading {
            readAgain = true
        } else {
            prepared = false
            prepare()
        }
    }

    /// Reads the voice list in the background, after launch and when voices change, so neither the first line
    /// nor the motion on screen waits for it.
    func prepare() {
        guard !prepared, !loading else { return }
        loading = true
        Voices.best { [weak self] best in self?.found(best) }
    }

    private func found(_ best: AVSpeechSynthesisVoice?) {
        loading = false
        voice = best
        prepared = true
        if readAgain {
            readAgain = false
            prepared = false
            prepare()
        }
    }

    func say(_ text: String) {
        guard isOn() else { return }
        // A line asked for before the background read is done reads the list now.
        if !prepared { found(Self.bestArabicVoice()) }
        generation &+= 1
        let line = generation
        cutCurrent()
        waiting = true
        let chime = voice == nil
        AudioSession.activate { [weak self] in
            guard let self else { return }
            guard self.generation == line else {
                // A newer line or a stop came first: this one is dropped, and the session goes off if nothing is left.
                self.releaseIfIdle()
                return
            }
            self.waiting = false
            if chime {
                self.playChime()
                return
            }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = self.voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
            self.current = utterance
            self.synthesizer.speak(utterance)
        }
    }

    /// Silence now: the line being said and any line waiting for the session.
    func stop() {
        generation &+= 1
        waiting = false
        cutCurrent()
        releaseIfIdle()
    }

    nonisolated static func bestArabicVoice() -> AVSpeechSynthesisVoice? {
        let arabic = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("ar") }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            preference.firstIndex(of: v.language.lowercased().replacingOccurrences(of: "_", with: "-")) ?? preference.count
        }
        return arabic.sorted { a, b in
            if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
            return rank(a) < rank(b)
        }.first
    }

    private func cutCurrent() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        current = nil
    }

    /// The synthesizer finished or cut a line.
    fileprivate func ended(_ line: AVSpeechUtterance) {
        if current === line { current = nil }
        releaseIfIdle()
    }

    /// Music comes back up once nothing is being said, waiting to be said, or chiming.
    private func releaseIfIdle() {
        guard current == nil, !waiting, player?.isPlaying != true else { return }
        AudioSession.release()
    }

    private func playChime() {
        if engine == nil { buildChime() }
        guard let engine, let player, let chimeBuffer else {
            releaseIfIdle()
            return
        }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else {
            releaseIfIdle()
            return
        }
        player.scheduleBuffer(chimeBuffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
        // The node keeps "playing" after its buffer ends: stop it, then let the music back up.
        chimeRelease?.cancel()
        chimeRelease = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            self.player?.stop()
            self.engine?.stop()
            self.releaseIfIdle()
        }
    }

    /// 880 Hz, then 1318.5 Hz 0.16 s later, each rising in 20 ms and fading over half a second.
    private func buildChime() {
        let rate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        let seconds = 0.75
        let frames = AVAudioFrameCount(rate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frames
        let tones: [(frequency: Double, start: Double)] = [(880, 0.01), (1318.5, 0.17)]
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            var value = 0.0
            for tone in tones where t >= tone.start && t < tone.start + 0.55 {
                let local = t - tone.start
                let gain: Double
                if local < 0.02 {
                    gain = 0.0001 * pow(0.16 / 0.0001, local / 0.02)
                } else {
                    gain = 0.16 * pow(0.0001 / 0.16, min(1, (local - 0.02) / 0.48))
                }
                value += gain * sin(2 * .pi * tone.frequency * local)
            }
            samples[i] = Float(value)
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        self.engine = engine
        self.player = player
        chimeBuffer = buffer
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    // The utterance goes to the main actor as it is: it is only compared there, never changed, and holding it
    // keeps its address from being reused by the next line before this word about it arrives.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let line = utterance
        Task { @MainActor in self.ended(line) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let line = utterance
        Task { @MainActor in self.ended(line) }
    }
}

/// The device's voice list, read on a queue of its own: the list comes from a synchronous call into the speech
/// service, which on a Swift concurrency thread holds that thread (Xcode 27's console said «unsafeForcedSync called
/// from Swift Concurrent context» when it was read in a detached task, build 5 on the MacBook Air).
nonisolated enum Voices {
    private static let queue = DispatchQueue(label: "Hmd.Sakka.voices", qos: .utility)

    /// `then` gets the best Arabic voice (or none) on the main actor.
    static func best(then: @escaping @MainActor @Sendable (AVSpeechSynthesisVoice?) -> Void) {
        queue.async {
            let best = Speaker.bestArabicVoice()
            Task { @MainActor in then(best) }
        }
    }
}

/// The shared audio session, switched on its own serial queue: activating and deactivating wait for the audio
/// hardware, so they never run on the main thread, and they run in the order they were asked for.
nonisolated enum AudioSession {
    private static let queue = DispatchQueue(label: "Hmd.Sakka.audio-session", qos: .userInitiated)

    /// Playback, spoken audio: heard with the Silent switch on; other audio ducks while it speaks.
    /// `then` runs on the main actor once the session is on (or failed to come on).
    static func activate(then: @escaping @MainActor @Sendable () -> Void) {
        queue.async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)
            Task { @MainActor in then() }
        }
    }

    /// Off again, telling other apps (music) they can come back up.
    static func release() {
        queue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
