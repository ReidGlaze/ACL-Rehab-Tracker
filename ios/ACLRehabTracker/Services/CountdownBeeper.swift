import AVFoundation

/// The self-timer's sound: a short beep each second and a longer, higher one when the photo is taken.
/// The tones are generated here so no audio files need shipping.
///
/// It plays even with the ring switch on silent (and mixes with any music), because the whole point
/// is hearing the count from across the room. The user turns the timer on themselves each time.
final class CountdownBeeper {
    private var tick: AVAudioPlayer?
    private var shutter: AVAudioPlayer?

    func prepare() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        if tick == nil { tick = Self.player(frequency: 880, seconds: 0.12) }
        if shutter == nil { shutter = Self.player(frequency: 1320, seconds: 0.45) }
        tick?.prepareToPlay()
        shutter?.prepareToPlay()
    }

    func playTick() {
        tick?.currentTime = 0
        tick?.play()
    }

    func playShutter() {
        shutter?.currentTime = 0
        shutter?.play()
    }

    func finish() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private static func player(frequency: Double, seconds: Double) -> AVAudioPlayer? {
        let player = try? AVAudioPlayer(data: wav(frequency: frequency, seconds: seconds))
        player?.volume = 1
        return player
    }

    /// A mono 16-bit WAV of a sine tone with a short fade at each end so it doesn't click.
    static func wav(frequency: Double, seconds: Double, sampleRate: Double = 44_100) -> Data {
        let count = Int(seconds * sampleRate)
        let fade = max(1, Int(0.01 * sampleRate))
        var samples = Data(capacity: count * 2)
        for i in 0..<count {
            let envelope = min(1, Double(min(i, count - 1 - i)) / Double(fade))
            let value = Int16(sin(2 * .pi * frequency * Double(i) / sampleRate) * envelope * 0.9 * Double(Int16.max))
            withUnsafeBytes(of: value.littleEndian) { samples.append(contentsOf: $0) }
        }

        func bytes<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8)); data.append(bytes(UInt32(36 + samples.count)))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); data.append(bytes(UInt32(16)))
        data.append(bytes(UInt16(1))); data.append(bytes(UInt16(1)))            // PCM, mono
        data.append(bytes(UInt32(sampleRate))); data.append(bytes(UInt32(sampleRate * 2)))
        data.append(bytes(UInt16(2))); data.append(bytes(UInt16(16)))
        data.append(contentsOf: Array("data".utf8)); data.append(bytes(UInt32(samples.count)))
        data.append(samples)
        return data
    }
}
