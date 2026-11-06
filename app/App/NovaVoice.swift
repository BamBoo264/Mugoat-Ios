import AVFoundation
import Foundation

/// Microphone is opt-in. Capture and playout queues are bounded independently of game state.
final class NovaVoice {
    private final class Capture {
        var phase = 0.0
        var frame = Data()
        func consume(_ buffer: AVAudioPCMBuffer, emit: (Data) -> Void) {
            guard let samples = buffer.floatChannelData?[0], buffer.format.sampleRate >= 8000 else { return }
            let step = 8000 / buffer.format.sampleRate
            for index in 0..<Int(buffer.frameLength) {
                phase += step
                if phase < 1 { continue }
                phase -= 1
                let input = samples[index]
                let value = input.isFinite ? max(-1, min(1, input)) : 0
                let sample = UInt16(bitPattern: Int16(value * 32767))
                frame.append(UInt8(truncatingIfNeeded: sample))
                frame.append(UInt8(truncatingIfNeeded: sample >> 8))
                if frame.count == 1600 {
                    emit(frame)
                    frame.removeAll(keepingCapacity: true)
                }
            }
        }
    }

    private final class Channel {
        let node = AVAudioPlayerNode()
        var queued = 0
        var lastUsed = Date.distantPast
    }
    private let audio = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
    private var channels: [String: Channel] = [:]
    private var generation = 0
    private var inRoom = false
    private var impactPlayer: AVAudioPlayer?
    private var tapInstalled = false
    private var configuring = false
    private var ownsRecordingCategory = false
    private(set) var microphoneEnabled = false
    var sendFrame: ((Data) -> Void)?
    var stateChanged: ((Bool) -> Void)?

    func setRoom(_ active: Bool) {
        guard inRoom != active else { return }
        inRoom = active
        if !active {
            stopMicrophone()
            impactPlayer?.stop()
            for channel in channels.values { channel.node.stop(); audio.detach(channel.node) }
            channels.removeAll()
            audio.stop()
        }
    }

    func toggleMicrophone() {
        if microphoneEnabled || configuring { stopMicrophone(); return }
        guard inRoom else { return }
        configuring = true
        let token = generation
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.inRoom else { return }
                self.configuring = false
                guard granted else {
                    self.stateChanged?(false)
                    GameFolder.log("Online voice: microphone permission denied.")
                    return
                }
                self.startMicrophone()
            }
        }
    }

    private func startMicrophone() {
        do {
            let session = AVAudioSession.sharedInstance()
            audio.stop()
            for channel in channels.values { channel.node.stop(); channel.queued = 0 }
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            ownsRecordingCategory = true
            try session.setActive(true)
            let input = audio.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate >= 8000, inputFormat.channelCount > 0 else { stopMicrophone(); return }
            let capture = Capture()
            let token = generation
            input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                capture.consume(buffer) { data in
                    DispatchQueue.main.async {
                        guard let self, self.generation == token, self.microphoneEnabled else { return }
                        self.sendFrame?(data)
                    }
                }
            }
            tapInstalled = true
            audio.prepare()
            try audio.start()
            microphoneEnabled = true
            stateChanged?(true)
        } catch {
            stopMicrophone()
            GameFolder.log("Online voice: audio setup failed: \(error.localizedDescription)")
        }
    }

    func stopMicrophone() {
        generation &+= 1
        configuring = false
        if tapInstalled { audio.inputNode.removeTap(onBus: 0); tapInstalled = false }
        microphoneEnabled = false
        stateChanged?(false)
        if ownsRecordingCategory {
            ownsRecordingCategory = false
            audio.stop()
            for channel in channels.values { channel.node.stop(); channel.queued = 0 }
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
    }

    /// A short synthesized impact for a collision simulated on another phone.
    func playVehicleImpact(distance: Float) {
        guard inRoom, distance < 35 else { return }
        if impactPlayer == nil {
            var wav = Data()
            func appendWord(_ value: UInt32, bytes: Int) {
                for index in 0..<bytes { wav.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
            }
            let sampleCount = 2400
            wav.append(contentsOf: "RIFF".utf8)
            appendWord(UInt32(36 + sampleCount * 2), bytes: 4)
            wav.append(contentsOf: "WAVEfmt ".utf8)
            appendWord(16, bytes: 4); appendWord(1, bytes: 2); appendWord(1, bytes: 2)
            appendWord(16000, bytes: 4); appendWord(32000, bytes: 4)
            appendWord(2, bytes: 2); appendWord(16, bytes: 2)
            wav.append(contentsOf: "data".utf8)
            appendWord(UInt32(sampleCount * 2), bytes: 4)
            var random: UInt32 = 0x4c52a711
            var filtered = 0.0
            for index in 0..<sampleCount {
                random ^= random << 13; random ^= random >> 17; random ^= random << 5
                let noise = Double(random & 0xffff) / 32768 - 1
                filtered = 0.64 * filtered + 0.36 * noise
                let time = Double(index) / 16000
                let wave = (0.63 * filtered + 0.37 * sin(time * 630)) * exp(-time * 34) * min(1, time * 900)
                let sample = Int16(max(-1, min(1, wave)) * 32767)
                appendWord(UInt32(UInt16(bitPattern: sample)), bytes: 2)
            }
            impactPlayer = try? AVAudioPlayer(data: wav)
        }
        impactPlayer?.volume = 0.55 * max(0.08, 1 - distance / 35)
        impactPlayer?.currentTime = 0
        impactPlayer?.play()
    }

    func play(_ data: Data, from peer: String) {
        guard inRoom, data.count == 1600 else { return }
        let channel: Channel
        if let existing = channels[peer] {
            channel = existing
        } else {
            if channels.count >= 4 {
                guard let oldest = channels.min(by: { $0.value.lastUsed < $1.value.lastUsed }),
                      Date().timeIntervalSince(oldest.value.lastUsed) >= 1 else { return }
                oldest.value.node.stop()
                audio.detach(oldest.value.node)
                channels.removeValue(forKey: oldest.key)
            }
            channel = Channel()
            audio.attach(channel.node)
            audio.connect(channel.node, to: audio.mainMixerNode, format: format)
            channels[peer] = channel
        }
        guard channel.queued < 2, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 800),
              let samples = buffer.floatChannelData?[0] else { return }
        if !audio.isRunning {
            do { try audio.start() } catch { return }
        }
        buffer.frameLength = 800
        data.withUnsafeBytes { bytes in
            let raw = bytes.bindMemory(to: UInt8.self)
            for index in 0..<800 {
                let sample = UInt16(raw[index * 2]) | (UInt16(raw[index * 2 + 1]) << 8)
                samples[index] = Float(Int16(bitPattern: sample)) / 32768
            }
        }
        channel.lastUsed = Date()
        channel.queued += 1
        channel.node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak channel] _ in
            DispatchQueue.main.async { if let channel { channel.queued = max(0, channel.queued - 1) } }
        }
        if !channel.node.isPlaying { channel.node.play() }
    }
}
