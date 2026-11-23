import Foundation

/// A self-recorded guitar clip from Fixtures/: a mono 16-bit PCM WAV file.
struct Clip {
    let samples: [Float]
    let sampleRate: Double

    struct UnreadableClip: Error { let reason: String }

    init(_ name: String) throws {
        guard let url = Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures") else {
            throw UnreadableClip(reason: "no Fixtures/\(name).wav")
        }
        let bytes = [UInt8](try Data(contentsOf: url))
        func integer(_ offset: Int, bytes count: Int) -> Int {
            (0..<count).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
        }
        func tag(_ offset: Int) -> String { String(decoding: bytes[offset..<offset + 4], as: UTF8.self) }

        guard bytes.count >= 12, tag(0) == "RIFF", tag(8) == "WAVE" else {
            throw UnreadableClip(reason: "\(name) is not a WAV file")
        }
        var rate: Double?
        var data: Range<Int>?
        var offset = 12
        while offset + 8 <= bytes.count {
            let size = integer(offset + 4, bytes: 4)
            let body = offset + 8
            guard body + size <= bytes.count else { throw UnreadableClip(reason: "\(name) is cut short") }
            switch tag(offset) {
            case "fmt ":
                guard size >= 16, integer(body, bytes: 2) == 1,
                      integer(body + 2, bytes: 2) == 1, integer(body + 14, bytes: 2) == 16 else {
                    throw UnreadableClip(reason: "\(name) is not mono 16-bit PCM")
                }
                rate = Double(integer(body + 4, bytes: 4))
            case "data":
                data = body..<body + size
            default:
                break
            }
            offset = body + size + size % 2     // chunks are padded to an even length
        }
        guard let rate, let data else { throw UnreadableClip(reason: "\(name) has no fmt or data chunk") }
        sampleRate = rate
        samples = stride(from: data.lowerBound, to: data.upperBound - 1, by: 2).map {
            Float(Int16(truncatingIfNeeded: integer($0, bytes: 2))) / 32_768
        }
    }
}
