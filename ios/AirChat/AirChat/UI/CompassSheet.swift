import SwiftUI

/// "Find My Friend" compass: a rotating arrow pointing to the target's GPS
/// location, with live distance. Observes the location manager directly so the
/// arrow animates as the user turns.
struct CompassSheet: View {
    @ObservedObject var store: ChatStore
    @ObservedObject var location: LocationManager
    let target: RoomUser

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Text(NSLocalizedString("looking_for", comment: ""))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(target.name).font(.title3.bold())
            }
            .padding(.top, 40)

            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 3)
                    .frame(width: 220, height: 220)
                Circle()
                    .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                    .frame(width: 150, height: 150)

                if let info = targetInfo {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.tint)
                        .rotationEffect(.degrees(rotation(for: info)))
                        .animation(.easeInOut, value: rotation(for: info))
                } else {
                    ProgressView()
                }
            }

            VStack(spacing: 4) {
                if let info = targetInfo {
                    Text(distanceText(for: info))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                } else {
                    Text(NSLocalizedString("searching_signal", comment: ""))
                        .foregroundStyle(.secondary)
                }
                Text(NSLocalizedString("distance", comment: ""))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#0A0A0A").ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private var targetInfo: (lat: Double, lon: Double)? {
        guard let lat = target.lat, let lon = target.lon,
              let myLoc = location.coordinate, lat != 0 || lon != 0 else {
            return nil
        }
        return (lat, lon)
    }

    private func rotation(for info: (lat: Double, lon: Double)) -> Double {
        guard let myLoc = location.coordinate else { return 0 }
        let b = bearingDegrees(lat1: myLoc.latitude, lon1: myLoc.longitude,
                               lat2: info.lat, lon2: info.lon)
        return b - location.heading
    }

    private func distanceText(for info: (lat: Double, lon: Double)) -> String {
        guard let myLoc = location.coordinate else {
            return NSLocalizedString("calculating", comment: "")
        }
        let d = distanceMetres(lat1: myLoc.latitude, lon1: myLoc.longitude,
                               lat2: info.lat, lon2: info.lon)
        if d < 1000 {
            return "\(Int(d.rounded())) " + NSLocalizedString("m_suffix", comment: "")
        } else {
            return String(format: "%.2f", d / 1000) + " " + NSLocalizedString("km_suffix", comment: "")
        }
    }
}
