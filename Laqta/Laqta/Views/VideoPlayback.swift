//
//  VideoPlayback.swift
//  Laqta
//
//  Plays saved videos inside the viewer, with Laqta's own glass controls.
//

import AVFoundation
import Foundation
import Observation
import SwiftUI
import UIKit

@Observable
final class VideoPlaybackModel {
    private(set) var itemID: UUID?
    private(set) var player: AVPlayer?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isReady = false
    var isScrubbing = false
    var isMuted = false {
        didSet { player?.isMuted = isMuted }
    }

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    /// Shows the video's length before it plays.
    func prepare(_ shot: Shot) {
        guard itemID != shot.id else { return }
        stop()
        itemID = shot.id
        duration = shot.mediaDuration ?? 0
        currentTime = 0
    }

    func toggle(_ shot: Shot) {
        if itemID == shot.id, isPlaying {
            pause()
        } else {
            play(shot)
        }
    }

    func play(_ shot: Shot) {
        prepare(shot)
        if player == nil {
            guard MediaWaiter.isAvailable(fileName: shot.fileName) else {
                CloudMediaStore.requestDownload(of: shot.fileName)
                return
            }
            load(shot)
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if duration > 0, currentTime >= duration - 0.2 {
            player?.seek(to: .zero)
        }
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to seconds: Double, in shot: Shot) {
        prepare(shot)
        if player == nil {
            play(shot)
        }
        let target = CMTime(seconds: max(0, min(seconds, duration > 0 ? duration : seconds)), preferredTimescale: 600)
        currentTime = target.seconds
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        if !isPlaying { play(shot) }
    }

    /// Moves while scrubbing, without the exact-frame cost.
    func scrub(to seconds: Double) {
        currentTime = seconds
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.2, preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    func skip(by seconds: Double) {
        guard player != nil else { return }
        scrub(to: max(0, min(duration, currentTime + seconds)))
    }

    func stop() {
        player?.pause()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        statusObservation?.invalidate()
        timeObserver = nil
        endObserver = nil
        statusObservation = nil
        player = nil
        isPlaying = false
        isReady = false
        itemID = nil
    }

    private func load(_ shot: Shot) {
        let item = AVPlayerItem(url: shot.fileURL)
        let player = AVPlayer(playerItem: item)
        player.isMuted = isMuted
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                let seconds = time.seconds
                if seconds.isFinite { self.currentTime = seconds }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
            }
        }
        statusObservation = item.observe(\.status, options: [.new]) { @Sendable [weak self] observed, _ in
            let ready = observed.status == .readyToPlay
            let seconds = observed.duration.seconds
            Task { @MainActor in
                guard let self else { return }
                self.isReady = ready
                if ready, seconds.isFinite, seconds > 0 {
                    self.duration = seconds
                }
            }
        }
        self.player = player
    }
}

/// An `AVPlayerLayer` that fits the video inside the page.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.accessibilityIgnoresInvertColors = true
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Play, scrub, time and sound, in a glass capsule.
struct VideoControls: View {
    let shot: Shot
    let playback: VideoPlaybackModel

    @Environment(\.laqta) private var palette
    @State private var scrubValue: Double = 0

    private var isCurrent: Bool { playback.itemID == shot.id }
    private var duration: Double { max(playback.duration, shot.mediaDuration ?? 0) }
    private var time: Double { isCurrent ? playback.currentTime : 0 }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                playback.toggle(shot)
            } label: {
                Image(systemName: isCurrent && playback.isPlaying ? "pause.fill" : "play.fill")
                    .laqtaIconFont(17, weight: .semibold)
                    .foregroundStyle(palette.goldHi)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(Text(isCurrent && playback.isPlaying ? "Pause" : "Play"))
            .largeContentLabel(Text(isCurrent && playback.isPlaying ? "Pause" : "Play"), systemImage: isCurrent && playback.isPlaying ? "pause.fill" : "play.fill")

            Text(verbatim: LaqtaFormat.duration(playback.isScrubbing ? scrubValue : time))
                .laqtaFont(12, weight: .medium, monospacedDigit: true, maxScale: 1.4)
                .foregroundStyle(palette.ink2)
                .frame(minWidth: 38)
                .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { playback.isScrubbing ? scrubValue : time },
                    set: { newValue in
                        scrubValue = newValue
                        if isCurrent { playback.scrub(to: newValue) }
                    }
                ),
                in: 0...max(duration, 0.1)
            ) { editing in
                if editing, !isCurrent {
                    playback.prepare(shot)
                }
                playback.isScrubbing = editing
                if !editing {
                    playback.seek(to: scrubValue, in: shot)
                }
            }
            .tint(palette.goldHi)
            .accessibilityLabel(Text("Position"))
            .accessibilityValue(Text(verbatim: "\(LaqtaFormat.spokenDuration(time)) of \(LaqtaFormat.spokenDuration(duration))"))

            Text(verbatim: "-" + LaqtaFormat.duration(max(0, duration - (playback.isScrubbing ? scrubValue : time))))
                .laqtaFont(12, weight: .medium, monospacedDigit: true, maxScale: 1.4)
                .foregroundStyle(palette.ink2)
                .frame(minWidth: 42)
                .accessibilityHidden(true)

            Button {
                playback.isMuted.toggle()
            } label: {
                Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .laqtaIconFont(14, weight: .semibold)
                    .foregroundStyle(palette.ink2)
                    .frame(width: 36, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(playback.isMuted ? "Turn Sound On" : "Mute"))
            .largeContentLabel(Text(playback.isMuted ? "Turn Sound On" : "Mute"), systemImage: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 8)
        .frame(minHeight: 52)
        .laqtaGlass(in: Capsule())
    }
}
