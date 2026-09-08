//
//  LocationProvider.swift
//  AirChat
//
//  GPS + compass for the "Find my friend" feature. On Android this is
//  LocationManager + SensorManager (accelerometer & magnetometer fused into an
//  azimuth, pushed into the WebView). On iOS the correct equivalent is
//  CLLocationManager for the position and CLLocationManager's own heading for the
//  azimuth — that is literally the same data source Safari exposes to web pages as
//  `deviceorientation.webkitCompassHeading`, so the host and the browser clients end
//  up with identical compass semantics.
//

import CoreLocation
import CoreMotion
import Foundation

protocol LocationProviderDelegate: AnyObject {
    func locationProvider(_ provider: LocationProvider, didUpdateLatitude lat: Double, longitude lon: Double)
    func locationProvider(_ provider: LocationProvider, didUpdateHeading degrees: Double)
    func locationProvider(_ provider: LocationProvider, didChangeAuthorization status: CLAuthorizationStatus)
}

final class LocationProvider: NSObject, CLLocationManagerDelegate {

    weak var delegate: LocationProviderDelegate?

    private let manager = CLLocationManager()
    private let motion = CMMotionManager()
    private var headingThrottle = Date.distantPast

    private(set) var lastLocation: CLLocation?
    private(set) var lastHeading: Double?
    private(set) var isRunning = false

    var authorizationStatus: CLAuthorizationStatus {
        if #available(iOS 14.0, *) { return manager.authorizationStatus }
        return CLLocationManager.authorizationStatus()
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.headingFilter = 3
        manager.activityType = .otherNavigation
    }

    func requestPermissionAndStart() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        start()
    }

    func start() {
        guard !isRunning else { return }
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        isRunning = true
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        // Only needed as a smoothing source for the heading when the magnetometer
        // reports low accuracy (e.g. the phone is lying flat).
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.2
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
                guard let self = self, let data = data else { return }
                self.lastMotionYaw = Double(data.attitude.yaw)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        motion.stopDeviceMotionUpdates()
    }

    private var lastMotionYaw: Double?

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // AirChat only needs metres-of-trust, not an audit trail; drop sub-50 m noise.
        if let previous = lastLocation, location.horizontalAccuracy > 60,
           location.distance(from: previous) < 8 { return }
        lastLocation = location
        delegate?.locationProvider(self, didUpdateLatitude: location.coordinate.latitude,
                                   longitude: location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        let now = Date()
        guard now.timeIntervalSince(headingThrottle) > 0.2 else { return }   // same 200 ms cadence as Android
        headingThrottle = now

        var value: CLLocationDirection = -1
        if heading.trueHeading >= 0 && heading.headingAccuracy <= 35 {
            value = heading.trueHeading
        } else if heading.magneticHeading >= 0 {
            value = heading.magneticHeading
        } else if let yaw = lastMotionYaw {
            // Rough fallback: yaw is counter-clockwise, compass is clockwise.
            value = (360.0 - (yaw * 180.0 / .pi)).truncatingRemainder(dividingBy: 360.0)
            if value < 0 { value += 360 }
        }
        guard value >= 0 else { return }
        let rounded = (value * 10).rounded() / 10
        lastHeading = rounded
        delegate?.locationProvider(self, didUpdateHeading: rounded)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        delegate?.locationProvider(self, didChangeAuthorization: status)
        if status == .authorizedWhenInUse || status == .authorizedAlways { start() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("AirChat: location error \(error.localizedDescription)")
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }
}
