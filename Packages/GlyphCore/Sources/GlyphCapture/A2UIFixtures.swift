// Five invented screens for the A2UI renderer's tests, previews and the demo harness (Harness/A2UIDemo).
// Made-up data only. Each is JSONL, one A2UI 1.0 message a line.
public enum A2UIFixtures {
    /// (name, JSONL), in the order the demo draws them.
    public static let all: [(name: String, jsonl: String)] = [
        ("time-picker", #"""
{"version":"1.0","createSurface":{"surfaceId":"when","catalogId":"dev.fru.glyph/catalog/v1"}}
{"version":"1.0","updateComponents":{"surfaceId":"when","components":[{"id":"root","component":"Card","child":"col"},{"id":"col","component":"Column","children":["times","exact","buttons"]},{"id":"times","component":"ChoicePicker","label":"This afternoon","displayStyle":"chips","variant":"mutuallyExclusive","options":[{"label":"3:00 PM","value":"15:00"},{"label":"3:30 PM","value":"15:30"},{"label":"4:00 PM","value":"16:00"}],"value":{"@path":"/choice"}},{"id":"exact","component":"DateTimeInput","label":"Or pick a time","enableTime":true,"value":{"@path":"/time"}},{"id":"buttons","component":"Row","justify":"end","align":"center","children":["skip","set"]},{"id":"skip-label","component":"Text","text":"Not today"},{"id":"skip","component":"Button","child":"skip-label","variant":"borderless","action":{"event":{"name":"skip"}}},{"id":"set-label","component":"Text","text":"Set reminder"},{"id":"set","component":"Button","child":"set-label","variant":"primary","action":{"event":{"name":"setReminder","context":{"choice":{"@path":"/choice"},"time":{"@path":"/time"}}}}}]}}
{"version":"1.0","updateDataModel":{"surfaceId":"when","path":"/","value":{"choice":["15:30"],"time":"15:30"}}}
"""#),
        ("place", #"""
{"version":"1.0","createSurface":{"surfaceId":"place","catalogId":"dev.fru.glyph/catalog/v1"}}
{"version":"1.0","updateComponents":{"surfaceId":"place","components":[{"id":"root","component":"Card","child":"col"},{"id":"col","component":"Column","children":["spot","row"]},{"id":"spot","component":"Place","name":"Lakeside Coffee","address":"120 Harbor Street, Duluth","latitude":46.7867,"longitude":-92.0995,"hours":"Open today until 6 PM"},{"id":"row","component":"Row","justify":"end","children":["save"]},{"id":"save-label","component":"Text","text":"Add to the trip"},{"id":"save","component":"Button","child":"save-label","variant":"primary","action":{"event":{"name":"addPlace","context":{"name":"Lakeside Coffee"}}}}]}}
"""#),
        ("renewals", #"""
{"version":"1.0","createSurface":{"surfaceId":"renewals","catalogId":"dev.fru.glyph/catalog/v1"}}
{"version":"1.0","updateComponents":{"surfaceId":"renewals","components":[{"id":"root","component":"Card","child":"col"},{"id":"col","component":"Column","children":["strip","remindrow"]},{"id":"strip","component":"DayStrip","start":"2026-11-23","days":7,"value":{"@path":"/day"},"marks":[{"date":"2026-11-24","label":"Car insurance renews","detail":"$412"},{"date":"2026-11-26","label":"Gym membership renews","detail":"$39"},{"date":"2026-11-28","label":"Domain name renews","detail":"$18"}]},{"id":"remindrow","component":"Row","justify":"end","children":["remind"]},{"id":"remind-label","component":"Text","text":"Remind me the day before each"},{"id":"remind","component":"Button","child":"remind-label","variant":"default","action":{"event":{"name":"remindRenewals"}}}]}}
{"version":"1.0","updateDataModel":{"surfaceId":"renewals","path":"/","value":{"day":"2026-11-24"}}}
"""#),
        ("spending", #"""
{"version":"1.0","createSurface":{"surfaceId":"spending","catalogId":"dev.fru.glyph/catalog/v1"}}
{"version":"1.0","updateComponents":{"surfaceId":"spending","components":[{"id":"root","component":"Card","child":"col"},{"id":"col","component":"Column","children":["chart","note"]},{"id":"chart","component":"Chart","kind":"bar","label":"Groceries, the last six weeks","currency":"USD","points":{"@path":"/weeks"}},{"id":"note","component":"Text","text":"Up $12 on the week before, still under the $120 you set.","variant":"caption"}]}}
{"version":"1.0","updateDataModel":{"surfaceId":"spending","path":"/","value":{"weeks":[{"label":"Oct 12","value":84.2},{"label":"Oct 19","value":102.5},{"label":"Oct 26","value":91.0},{"label":"Nov 2","value":76.4},{"label":"Nov 9","value":98.3},{"label":"Nov 16","value":110.1}]}}}
"""#),
        ("todos", #"""
{"version":"1.0","createSurface":{"surfaceId":"todos","catalogId":"dev.fru.glyph/catalog/v1"}}
{"version":"1.0","updateComponents":{"surfaceId":"todos","components":[{"id":"root","component":"Card","child":"col"},{"id":"col","component":"Column","children":["list","buttons"]},{"id":"list","component":"List","children":{"path":"/todos","componentId":"todo"}},{"id":"todo","component":"TodoItem","title":{"@path":"title"},"time":{"@path":"time"},"tags":{"@path":"tags"},"done":{"@path":"done"}},{"id":"buttons","component":"Row","justify":"end","align":"center","children":["no","yes"]},{"id":"no-label","component":"Text","text":"Not now"},{"id":"no","component":"Button","child":"no-label","variant":"borderless","action":{"event":{"name":"dismiss"}}},{"id":"yes-label","component":"Text","text":"Add all three"},{"id":"yes","component":"Button","child":"yes-label","variant":"primary","action":{"event":{"name":"addTodos","context":{"todos":{"@path":"/todos"}}}}}]}}
{"version":"1.0","updateDataModel":{"surfaceId":"todos","path":"/","value":{"todos":[{"title":"Pick up rice","time":"After work","tags":["Groceries"],"done":false},{"title":"Call the dentist","time":"Tomorrow 9:00 AM","tags":["Health"],"done":false},{"title":"Renew the car tabs","time":"Friday","tags":["Car","Errands"],"done":false}]}}}
"""#),
    ]
}
