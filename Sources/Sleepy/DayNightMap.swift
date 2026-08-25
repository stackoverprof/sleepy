import AppKit
import SleepyCore

/// Draws the world as an equirectangular image shaded by where the sun is
/// shining right now.
enum DayNightMap {
    /// Grey levels for the four combinations the map shades: land or ocean,
    /// lit or dark. Twilight is a blend between a pair.
    enum Palette {
        static let oceanDay = 0.17
        static let oceanNight = 0.035
        static let landDay = 0.62
        static let landNight = 0.22
    }

    /// Elevation, in degrees, where the twilight blend reaches full night.
    /// A wide band keeps the edge of the midnight sun a gradient rather than
    /// a hard line drawn across the top of the map.
    private static let twilightFloor = -12.0

    /// Latitudes beyond this are cropped away. They are pure ocean on one end
    /// and a featureless ice cap on the other, and equirectangular smears both
    /// across the full width of the plate.
    static let visibleLatitude = 84.0

    static var aspectRatio: Double { 360 / (visibleLatitude * 2) }

    static func image(for solar: SolarPosition) -> NSImage? {
        let mask = WorldLandMask.world
        let width = mask.columns
        let firstRow = Int((90 - visibleLatitude) / 180 * Double(mask.rows))
        let height = mask.rows - firstRow * 2

        // The horizon sits at a sine of zero, so blending on the sine of the
        // elevation saves an asin per pixel and looks the same.
        let floorSine = sin(twilightFloor * .pi / 180)

        var cosineHourAngle = [Double](repeating: 0, count: width)
        for column in 0..<width {
            let longitude = -180 + (Double(column) + 0.5) * 360 / Double(width)
            cosineHourAngle[column] = cos((longitude - solar.subsolarLongitude) * .pi / 180)
        }

        let declination = solar.subsolarLatitude * .pi / 180
        let sineDeclination = sin(declination)
        let cosineDeclination = cos(declination)

        var pixels = [UInt8](repeating: 255, count: width * height * 4)

        for row in 0..<height {
            let maskRow = row + firstRow
            let latitude = (90 - (Double(maskRow) + 0.5) * 180 / Double(mask.rows)) * .pi / 180
            let sineLatitude = sin(latitude)
            let cosineLatitude = cos(latitude)

            for column in 0..<width {
                let sineElevation = sineLatitude * sineDeclination
                    + cosineLatitude * cosineDeclination * cosineHourAngle[column]
                let daylight = smoothstep((sineElevation - floorSine) / -floorSine)

                let land = mask.isLand(row: maskRow, column: column)
                let dark = land ? Palette.landNight : Palette.oceanNight
                let lit = land ? Palette.landDay : Palette.oceanDay
                let grey = channel(dark + (lit - dark) * daylight)

                let offset = (row * width + column) * 4
                pixels[offset] = grey
                pixels[offset + 1] = grey
                pixels[offset + 2] = grey
            }
        }

        guard
            let cgImage = pixels.withUnsafeMutableBytes({ buffer -> CGImage? in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress,
                        width: width,
                        height: height,
                        bitsPerComponent: 8,
                        bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    )
                else {
                    return nil
                }
                return context.makeImage()
            })
        else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private static func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private static func channel(_ value: Double) -> UInt8 {
        UInt8(min(max(value, 0), 1) * 255)
    }
}
