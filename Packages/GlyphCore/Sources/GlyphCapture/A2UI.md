# A2UI in Glyph: the Glyph catalog

Generative UI for the Glyph apps follows Google's A2UI 1.0 message format
(https://a2ui.org/specification/v1.0-a2ui/) and is drawn by our own code: `A2UI.swift` (the messages, a
surface's components and data model) and `A2UIView.swift` (the SwiftUI drawing, iOS and macOS). No Google
package and no new dependency (the owner's call, 2026-11-22). Field names are the spec's, so an official
renderer could take over later.

Catalog id: **`dev.fru.glyph/catalog/v1`**. An app says it draws it per turn, as the spec has it:
`{"a2uiRendererCapabilities": {"1.0": {"supportedCatalogIds": ["dev.fru.glyph/catalog/v1"]}}}`
(`Hub.understand(..., supportedCatalogIds: [A2UI.catalogId])` sends it). The hub checks every screen against
this list (`server/jot-inbox.py`, `A2UI_PARTS`; keep the two in step) and drops what does not fit, so a bad
generation never reaches a phone.

## Messages

One JSON object per message, each `{"version": "1.0", <one of>}`:

| Message | Fields |
|---|---|
| `createSurface` | `surfaceId`, `catalogId`, optional `components`, `dataModel`, `sendDataModel` |
| `updateComponents` | `surfaceId`, `components`: a flat list, each `{"id", "component": <part>, ...properties}`; one has id `root`; children by id |
| `updateDataModel` | `surfaceId`, `path` (JSON Pointer, default `/`), `value` (`null` removes) |
| `deleteSurface` | `surfaceId` |

Back to the hub (POST `/a2ui/action`, `Hub.answer(action:surface:history:)`):
`{"version": "1.0", "action": {"name", "surfaceId", "sourceComponentId", "timestamp", "context", "userMessage"}}`,
with the button's `context` bindings resolved from the data model when it was pressed.

Values: a literal, or a binding `{"@path": "/pointer"}` (relative, `{"@path": "title"}`, inside a List
template's item). Inputs write to their bound path at once, locally; the hub only hears of it through an
action's context. `@call` functions are not drawn yet (logged, nothing shown). Any part may carry `weight`
(a number, inside a Row or Column: that child takes the free width).

Drawing rules: a part not in this catalog draws nothing and is logged once when it arrives; a child named
before it arrives draws as a quiet placeholder; a cycle stops at depth 40. Never a crash.

## The Basic Catalog parts it draws

| Part | Properties (**bold** = required) | Notes |
|---|---|---|
| `Text` | **`text`**, `variant`: `body` (default), `caption`, `title` | inline Markdown; `title` is a Glyph addition |
| `Image` | **`url`**, `description`, `fit`: `contain` `cover` `fill` `none` `scaleDown`, `variant`: `icon` `avatar` `smallFeature` `mediumFeature` `largeFeature` `header` | |
| `Icon` | **`name`**: the Basic Catalog's names (`calendarToday`, `locationOn`, `check`...) | drawn as SF Symbols |
| `Row` | **`children`**, `justify`: `start` `center` `end` `spaceBetween` `spaceAround` `spaceEvenly` `stretch`, `align`: `start` `center` `end` `stretch` | |
| `Column` | **`children`**, `align` (`stretch` default), `justify` | `justify` reads as start |
| `List` | **`children`** (ids, or a template `{"path", "componentId"}`), `direction`: `vertical` `horizontal`, `align` | hairlines between vertical items |
| `Card` | **`child`** | the composer's dark ground, 20 pt corners |
| `Divider` | `axis`: `horizontal` `vertical` | |
| `Button` | **`child`** (a Text), **`action`**: `{"event": {"name", "context", "userMessage"}}` or `{"functionCall": {"@call": "openUrl", "args": {"url"}}}`, `variant`: `default` `primary` `borderless` | primary is the app's tint with white; the Text's words become my chat line |
| `CheckBox` | **`label`**, **`value`** (boolean) | |
| `TextField` | **`label`**, **`value`**, `placeholder`, `variant`: `shortText` `longText` `number` `obscured` | |
| `DateTimeInput` | **`value`** (`"15:30"`, `"2026-11-24"` or `"2026-11-24T15:30"`), `enableDate`, `enableTime`, `min`, `max`, `label` | writes back in the value's own form |
| `ChoicePicker` | **`options`** `[{"label", "value"}]`, **`value`** (a list of values), `label`, `variant`: `mutuallyExclusive` `multipleSelection`, `displayStyle`: `checkbox` `chips` | chips are the family's tag chips, chosen in full office green |
| `Slider` | **`value`**, **`max`**, `min`, `label`, `steps` | |

Not drawn in phase A: `Video`, `AudioPlayer`, `Tabs`, `Modal` (they are not in the Glyph catalog, so the hub
drops them).

## The Glyph parts

| Part | Properties | What it draws |
|---|---|---|
| `Place` | **`name`**, `address`, `latitude`, `longitude`, `hours`, `action` | a dark MapKit still with an office-green pin (`MKMapSnapshotter`; `A2UIMap.prepare(surface)` fetches it ahead), the name, address and hours, and Open in Maps |
| `DayStrip` | `start` (a date, default today), `days` (1 to 14, default 7), `marks` `[{"date", "label", "detail"}]` (or a binding), `value` (the chosen date, bound), `action` | a strip of days, a green dot under each marked one, the chosen day filled; under it each mark as a line: date, label, detail |
| `Chart` | `kind`: `bar` `line`, `label`, **`points`** `[{"label", "value"}]` (or a binding), `unit`, `currency` (ISO code) | Swift Charts, 150 pt: the label and the latest value, the latest bar full green and the rest faded |
| `TodoItem` | **`title`**, `time`, `tags` (names), `done` (boolean, bound), `action` | a done circle, the title, the time and `#Tag`s in the register's colours |
| `TagChip` | **`name`**, `action` | the family's `#` chip, compact |

## Fixtures

`A2UIFixtures.all`: five invented screens (a time picker clarification, a Place card, a DayStrip with three
renewals, a spending Chart, a TodoItem list), used by `Tests/GlyphCaptureTests/A2UITests.swift` and the demo
harness `Harness/A2UIDemo` (`scripts/a2ui-shots.sh <out>` pictures them on an iPhone simulator and the Mac).
