import Foundation
import Testing
@testable import GlyphVault

private func object(_ line: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] ?? [:]
}

/// Every app line carries where it was saved: `place`, `lat`, `lon` (6 decimals), beside its `device`.
@Test func linesCarryWhereTheyWereSaved() {
    let here = Where(place: " Elm Street, Springfield ", lat: 44.97775312345, lon: -93.26501987654)
    #expect(here.place == "Elm Street, Springfield")
    #expect(here.lat == 44.977753 && here.lon == -93.26502)

    let well = WellLine.log(id: "a", kind: "mood", name: "Calm", said: "calm", at: .now, host: "iphone-x", device: "iPhone X", where: here)
    #expect(well.contains(#""lat":44.977753"#) && well.contains(#""lon":-93.26502"#))
    let o = object(well)
    // Well's `place` is a CRM id: the name goes in `from`.
    #expect(o["from"] as? String == "Elm Street, Springfield" && o["place"] == nil && o["device"] as? String == "iPhone X")
    #expect(o["lat"] as? Double == 44.977753)

    // Each writer stamps it.
    let lines = [
        WealthLine.log(id: "b", kind: "spend", name: "Coffee", cents: -450, at: .now, host: "h", device: "d", said: "coffee", where: here),
        LifeLine.decide(id: "c", app: "acme", choice: "keep", amount: 9, host: "h", device: "d", where: here),
        LifeLine.start(id: "r", loop: "renewal", domain: "home", steps: 2, host: "h", device: "d", where: here),
        TravelLine.plan(id: "p", name: "Museum", trip: "Rome", day: "", reference: "", host: "h", device: "d", where: here),
        TravelLine.note(id: "n", text: "Closed on Mondays", trip: "Rome", host: "h", device: "d", where: here),
        String(decoding: JotMemo.body(text: "hi", tags: [], device: "d", where: here), as: UTF8.self),
    ]
    for l in lines { #expect(Where(object(l)) == here, "\(l)") }

    // No place: nothing written, never a guess. A fix with no name keeps its coordinates only.
    let none = object(WellLine.log(id: "a", kind: "mood", name: "Calm", said: "calm", at: .now, host: "h", device: "d"))
    #expect(none["place"] == nil && none["lat"] == nil && Where(none) == nil)
    let unnamed = object(WellLine.log(id: "a", kind: "mood", name: "Calm", said: "calm", at: .now, host: "h", device: "d",
                                      where: Where(place: "", lat: 1, lon: 2)))
    #expect(unnamed["place"] == nil && unnamed["from"] == nil && unnamed["lat"] as? Double == 1)

    // The item's screen line: its own device and place.
    #expect(Where.shown(device: "iPhone X", place: "Elm Street") == "iPhone X · Elm Street")
    #expect(Where.shown(device: "Studio Mac", place: nil) == "Studio Mac")
    #expect(Where.shown(device: nil, place: " ") == nil)
}

/// Six decimals in the file, whatever the Double; and a Time line keeps its place.
@Test func coordinatesPrintSixDecimalsAndTimeLinesCarryThem() throws {
    let w = Where(place: "Oak Park", lat: 36.123457, lon: -115.1)
    let line = WellLine.log(id: "a", kind: "mood", name: "Calm", said: "calm", at: .now, host: "h", device: "d", where: w)
    #expect(line.contains(#""lat":36.123457,"# ) && line.contains(#""lon":-115.1,"#), "\(line)")
    let e = TimeEvent("reminder", host: "iphone-x", device: "iPhone X", label: "Call Ken", where: w)
    let back = try JSONDecoder().decode(TimeEvent.self, from: JSONEncoder().encode(e))
    #expect(back.place == "Oak Park" && back.lat == 36.123457 && back.lon == -115.1 && back.device == "iPhone X")
    let bare = String(decoding: try JSONEncoder().encode(TimeEvent("reminder", host: "h")), as: UTF8.self)
    #expect(!bare.contains("lat") && !bare.contains("place"))
}

/// 2026-11-23: a plan said kind "medicine" for two supplements and Well filed both as notes.
@Test func wellLinesTakeTheEverydayWordForAKind() throws {
    #expect(WellLine.kind(of: "medicine") == "med")
    #expect(WellLine.kind(of: "Supplement") == "med")
    #expect(WellLine.kind(of: "workout") == "activity")
    #expect(WellLine.kind(of: "stool") == "stool")
    #expect(WellLine.kind(of: "banana") == "note")
    let line = WellLine.log(id: "w1", kind: "medicine", name: "Vitamin D", said: "vitamin d daily", at: .now,
                            host: "phone", device: "iPhone")
    let o = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    #expect(o?["kind"] as? String == "med")
}
