import Testing
@testable import ListenCore

@Suite struct InputMeterScaleTests {
    @Test(arguments: [(-90, 0), (-60, 0), (-30, 0.5), (0, 1), (6, 1), (-.infinity, 0)] as [(Double, Double)])
    func fractionIsLinearInDecibels(dBFS: Double, fraction: Double) {
        #expect(InputMeterScale.fraction(dBFS: dBFS) == fraction)
    }

    @Test func peakCountsNegativeSamples() {
        let peak = [0.1, -0.5, 0.25].map(Float.init).withUnsafeBufferPointer(InputMeterScale.peakDBFS)
        #expect(abs(peak - -6.0206) < 0.001)
    }

    @Test(arguments: [[], [0, 0]] as [[Float]]) func silenceIsMinusInfinity(samples: [Float]) {
        #expect(samples.withUnsafeBufferPointer(InputMeterScale.peakDBFS) == -.infinity)
    }
}
