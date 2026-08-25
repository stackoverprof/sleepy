import Testing
@testable import SleepyCore

@Test
func landMaskDecodes() {
    let mask = WorldLandMask.world

    #expect(mask.isAvailable)
    #expect(mask.columns == 720)
    #expect(mask.rows == 360)
}

@Test
func landMaskKnowsContinentsFromOceans() {
    let mask = WorldLandMask.world

    #expect(mask.isLand(latitude: 39.0, longitude: -98.0))    // Kansas
    #expect(mask.isLand(latitude: 48.85, longitude: 2.35))    // Paris
    #expect(mask.isLand(latitude: -25.0, longitude: 133.0))   // central Australia
    #expect(mask.isLand(latitude: -6.2, longitude: 106.8))    // Java
    #expect(mask.isLand(latitude: -80.0, longitude: 0.0))     // Antarctica
    #expect(mask.isLand(latitude: -89.5, longitude: 100.0))   // south polar cap

    #expect(!mask.isLand(latitude: 0.0, longitude: -140.0))   // Pacific
    #expect(!mask.isLand(latitude: 30.0, longitude: -40.0))   // Atlantic
    #expect(!mask.isLand(latitude: -40.0, longitude: 80.0))   // Indian Ocean
    #expect(!mask.isLand(latitude: 89.5, longitude: 0.0))     // Arctic Ocean
}

@Test
func landMaskWrapsLongitudeAndClampsLatitude() {
    let mask = WorldLandMask.world

    #expect(mask.isLand(latitude: 39.0, longitude: -98.0 + 360))
    #expect(mask.isLand(latitude: 39.0, longitude: -98.0 - 360))
    #expect(mask.isLand(latitude: -95.0, longitude: 0.0))
    #expect(!mask.isLand(latitude: 95.0, longitude: 0.0))
}
