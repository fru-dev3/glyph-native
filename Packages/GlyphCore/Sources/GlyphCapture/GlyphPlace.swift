import CoreLocation
import GlyphVault
import MapKit

/// Where the phone is, and what that place is called. Lifted out of Glyph Jot, which has done
/// this since its jots began, so Glyph Wealth and anything else asks the same question the same
/// way rather than writing a second CoreLocation path (Fru, 2026-11-10: "we've already done all
/// of this with Jot, you're not reinventing the wheel here").
///
/// Nothing here writes anything. It answers where you are and what it is called; what an app does
/// with that is the app's own business.
///
/// The Mac asks the same way (2026-11-23, "location and device is for all apps and desktop"): an app
/// that wants it carries `NSLocationUsageDescription` and, sandboxed, the location entitlement; without
/// them the answer is nil and nothing is asked.
@MainActor
public enum GlyphPlace {
    /// Where an item is being saved, named: one fix (`within` at most) and its name. Nil when location is
    /// off or no fix came, never a guess. Write the item first and add this after: nothing waits on it.
    public static func here(within: Duration = .seconds(15)) async -> Where? {
        guard let fix = await fix(within: within) else { return nil }
        return Where(place: await name(for: fix), lat: fix.coordinate.latitude, lon: fix.coordinate.longitude)
    }

    /// A fix, or nil: location refused, or nothing within thirty seconds.
    public static func fix(within: Duration = .seconds(30)) async -> CLLocation? {
        #if os(macOS)
        // The Mac has no CLServiceSession: the manager asks once, and stays alive while the fix comes.
        let manager = CLLocationManager()
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        defer { withExtendedLifetime(manager) {} }
        #endif
        // At the deadline, the best fix seen so far rather than none: indoors a 50 m fix may never come.
        let seen = Seen()
        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask { await best(seen) }
            group.addTask { try? await Task.sleep(for: within); return seen.value }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// The first fix within 50 m, or the best one after 10 seconds.
    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var best: CLLocation?
        var value: CLLocation? { lock.withLock { best } }
        func offer(_ l: CLLocation) { lock.withLock { if l.horizontalAccuracy < (best?.horizontalAccuracy ?? .infinity) { best = l } } }
    }

    nonisolated static func best(_ seen: Seen = Seen()) async -> CLLocation? {
        #if os(iOS)
        let session = CLServiceSession(authorization: .whenInUse) // asks once, the first time
        defer { session.invalidate() }
        #endif
        let deadline = Date.now.addingTimeInterval(10)
        var best: CLLocation?
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted { return nil }
                if let l = update.location, l.horizontalAccuracy >= 0, l.horizontalAccuracy < (best?.horizontalAccuracy ?? .infinity) { best = l; seen.offer(l) }
                if let best, best.horizontalAccuracy <= 50 || Date.now > deadline { return best }
            }
        } catch {}
        return best
    }


    /// What that place is called, for a line a person reads.
    /// A named place within 150 m (the gym, the park), else the street and town.
    /// Where a jot was made: the street or the neighbourhood, never the nearest shop.
    ///
    /// This used to ask for points of interest within 150 metres and take the closest, so a
    /// jot was labelled with whatever business happened to be nearby: ProEd, Bluemercury,
    /// Bitcoin Depot. That is precise about a till and wrong about a person (Fru,
    /// 2026-11-07: "this is not a commercial thing, this is my personal app"). The address
    /// answers the question actually being asked, which is where you were.
    ///
    /// A point of interest is still the last resort, because somewhere named is better than
    /// nothing at all when the map has no address to give.
    public static func name(for location: CLLocation) async -> String? {
        if let request = MKReverseGeocodingRequest(location: location),
           let item = try? await request.mapItems.first {
            let city = item.addressRepresentations?.cityName
            if let street = item.address?.shortAddress, !street.isEmpty {
                guard let city, !street.localizedCaseInsensitiveContains(city) else { return street }
                return "\(street), \(city)"
            }
            if let city, !city.isEmpty { return city }
        }
        let search = MKLocalSearch(request: MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 150))
        guard let items = try? await search.start().mapItems,
              let near = items.min(by: { $0.location.distance(from: location) < $1.location.distance(from: location) }),
              let name = near.name else { return nil }
        let city = near.addressRepresentations?.cityName
        return city.map { $0 == name ? name : "\(name), \($0)" } ?? name
    }
}
