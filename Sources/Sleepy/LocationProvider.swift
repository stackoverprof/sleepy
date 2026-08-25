import CoreLocation
import SleepyCore

/// Where the Mac is, for the prayer times and the marker on the map.
///
/// Location Services is asked for a fix, but the time zone's own coordinate
/// stands in until one arrives, and whenever permission is refused. That keeps
/// the map useful without the app depending on an answer.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private enum DefaultsKey {
        static let latitude = "lastKnownLatitude"
        static let longitude = "lastKnownLongitude"
    }

    private let manager = CLLocationManager()

    private(set) var coordinate: Coordinate?
    var onChange: (() -> Void)?

    override init() {
        super.init()
        coordinate = Self.remembered() ?? TimeZoneCoordinate.coordinate()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        default:
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status != .notDetermined {
                self.start()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let fix = locations.last else { return }
        let coordinate = Coordinate(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude
        )
        Task { @MainActor in self.apply(coordinate) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // The fallback coordinate stays in place; there is nothing to report.
    }

    private func apply(_ coordinate: Coordinate) {
        guard coordinate != self.coordinate else { return }
        self.coordinate = coordinate
        UserDefaults.standard.set(coordinate.latitude, forKey: DefaultsKey.latitude)
        UserDefaults.standard.set(coordinate.longitude, forKey: DefaultsKey.longitude)
        onChange?()
    }

    private static func remembered() -> Coordinate? {
        let defaults = UserDefaults.standard
        guard
            defaults.object(forKey: DefaultsKey.latitude) != nil,
            defaults.object(forKey: DefaultsKey.longitude) != nil
        else {
            return nil
        }
        return Coordinate(
            latitude: defaults.double(forKey: DefaultsKey.latitude),
            longitude: defaults.double(forKey: DefaultsKey.longitude)
        )
    }
}
