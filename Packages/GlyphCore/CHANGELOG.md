# Changelog

GlyphCore follows semantic versioning (the number is in `VERSION`). A change that alters
the on-disk format or breaks the public API is a major version, a new API a minor one, a
fix a patch. Every change gets a line here, so an app can see what moved before it updates.

## 0.23.0: the sidebar foot is one row (2026-11-27)

- `GlyphSidebarFoot`, design A of the foot board (Fru, 2026-11-27): one 44pt row under a hairline, the gear
  (an X that says "Back" while `settingsOpen`), the vault's state filling the middle, the iPhone icon, and the
  round coffee button. It was two rows, the coffee bar above the gear's line.
- One set of words: "Saving to your vault" / "Saving on this Mac", or with `reads: true` "Reading your vault" /
  "Vault not found". `detail` adds an app's own status after them ("Reading your vault · 1 h old") and
  `refresh` makes a click on them read again, with a mark on hover. `app` names the app for the support page.
- `GlyphSupportButton(app:)`: the coffee as a 32pt office green circle, hidden by the same Settings switch.

## 0.22.0: one search field and one way back from Settings on every Mac sidebar (2026-11-27)

- `GlyphSidebarSearch(text:prompt:focus:onSubmit:)`: the always-visible field under `GlyphSidebarHeader`,
  Glyph Jot's (28pt, 7pt corners, magnifier, clear button). Command-F puts the cursor in it, Esc clears it,
  `focus` lets a menu item do the same. Only the field is shared; each app keeps what its words find.
- `GlyphSidebarFoot(settingsOpen:back:)`: while settings shows, the gear is filled and tinted, says "Back"
  and runs `back`, as Glyph Jot's does. Both default off, so nothing changes for an app that passes neither.

## 0.21.0: every app's chat can draw the hub's screens (2026-11-24)

- `Hub.screens(for:)`: what a chat turn passes as `supportedCatalogIds`, the Glyph catalog unless that
  surface is answered by a local open model (which broke every turn when offered screens).
- `[ChatEntry].drawing(_:)`: puts the plan's A2UI screen under the turn's first line, dropping one
  with nothing to draw. `ChatModel.lines` uses it, so Glyph X's screens behave as before.
- `GlyphTag.count`: how many app entries are filed under a tag, as the hub counts them from the files
  (`/crm/names`). Nil when not known.

## 0.20.0: every top line fits, and the shared sheets say whose they are (2026-11-24)

- `GlyphHeaderLine(app:page:home:mark:)`: the top line's one layout, for any mark. Where the full
  line (mark, app name, dot, page name) does not fit, as between a sheet's Cancel and Save on an
  iPhone SE or at the largest text, it drops the app's words and keeps the mark and the whole page
  name, instead of cutting the page name. `GlyphPageHeader` draws through it.
- `GlyphApp` and `\.glyphApp`: which app this is (name, mark, tint, or a drawn mark), set once by
  the shell beside `\.glyphHome`.
- `GlyphSheetTitle(_:)`: a shared sheet's title, the app's top line when `\.glyphApp` is set. Used
  by the New tag / Edit tag form and Past chats, which showed a plain title in every app.

## 0.19.2: the app's name in the top line never wraps (2026-11-23)

`GlyphPageHeader` keeps the app's name on one line (`lineLimit(1)`, `fixedSize`); in a narrow
principal slot (Glyph Jot's tag page, with Back and a menu either side) "Glyph Jot" broke onto
two lines. The page's name is the part that shrinks.

## 0.19.1: Glyph Native holds every tag (2026-11-23)

- `GlyphTag.belongs(to: "native")` is true for every tag, as for Glyph CRM and Glyph Jot: Native's chat sends to any
  app, so its drawer lists them all.

## 0.19.0: the drawer's tags can carry counts, an order and a menu (2026-11-23)

- `GlyphDrawerTags(counts:order:menu:extra:)`: a count per tag at the row's end, the app's own order (Glyph Jot's
  Edit Order), what a long press offers (Jot's rename, describe, delete) and one more row under the tags. All
  optional; nothing changes for an app that passes none.

## 0.18.1: the drawer's tag heading has its own name (2026-11-23)

- `GlyphDrawerTags` heading is `drawer.tagsection` (and `drawer.tagsection.manage`): `drawer.tags` is every app's
  Tags place row, and two elements answering to one name made checks tap the wrong one.

## 0.18.0: chat with a tag from its page (2026-11-23)

- `GlyphTagComposer(tag:tint:)`: the family composer at the foot of a tag's page; what is said goes to the app's
  chat as the next turn with that tag (`ChatModel.say(_:tag:)`). The shell sets two environment values:
  `glyphAskInChat` (store the words, show the chat) and `glyphChatAsk` (the binding `GlyphChat` reads and clears).
  Fru: "when I click on the tag, I can just chat or interact with that tag."

## 0.17.0: the tags in every drawer (2026-11-23)

- `GlyphDrawerTags(app:tint:here:open:)`: every tag the app holds (`GlyphTags.forApp`), listed in the drawer under
  the places, open by default; its heading folds it away and the phone keeps that choice per app. A tag hands the
  app its `GlyphTag` to open that tag's page. Every app but Glyph CRM ends the list with Manage tags, which opens
  `glyph-crm://tags`. Fru: "I should see the chat, the app, and then the tags visible, showing all on the side,
  expanded. And then I can choose to collapse it or not."
- `GlyphDrawer(tags:)` draws it; a drawer an app still draws itself embeds the same view.

## 0.16.0: the composer can hold a screen's words, and send files alone (2026-11-23)

- `GlyphComposer(text:)` keeps the field and a screen's own string as one, so a screen can put words in the
  box (Glyph Bot's phone chat: a message that never reached the Mac comes back; words said on its home screen
  wait in an agent's box). nil, the default, changes nothing.
- `GlyphComposer(ready:)`: something besides words is waiting (Bot's attached files), so the send arrow shows
  with the field empty and sends an empty sentence for the screen to fill in.

## 0.15.1: a Well line keeps its place for Glyph CRM (2026-11-23)

- `WellLine.log(where:)` writes the place's name to `from`, as Glyph Well does, beside `lat` and `lon`. In
  a Well line `place` is a Glyph CRM id (Labs groups results by it); 0.14.0 put a street name there.

## 0.15.0: Time's lines carry a place; six decimals, and a fix at the deadline (2026-11-23)

- `TimeEvent` has `place`, `lat`, `lon` (optional, Codable; old lines read as before) and its init takes
  `where:`, so Glyph Time's timers, alarms and reminders can say where they were set.
- `Where.fields` writes the coordinates as decimals: a Double through JSONSerialization could print
  36.123457000000002.
- `GlyphPlace.fix(within:)` answers the best fix seen so far at the deadline rather than none, so a short
  wait indoors (no 50 m fix) still gets a place.

## 0.14.1: an agent's item names the device alone, and its memo says where (2026-11-23)

- `Hub.device` is the model ("iPhone 15 Pro", the Mac's name), as every app writes `device`; it was
  "<app>, <model>". Every agent line and memo changes with it.
- `MacHub.memo` writes `place`, `lat`, `lon` beside `device`, byte for byte the hub's save() (place quoted,
  6 decimals), so an agent's memo on the Mac carries `Hub.place` as the phone's does through the hub.

## 0.14.0: every line says where it was saved (2026-11-23)

Fru, 2026-11-23: "Location and device is for all apps and desktop."
- New `Where` (GlyphVault): `place` (the name, left out when the lookup had none), `lat`, `lon` (6
  decimals). `Where.stamp` adds them to a line, `Where(_:)` reads them back, `Where.shown(device:place:)`
  is the line an item's screen shows ("iPhone 17 Pro · Elm Street, Springfield"), from the item's own record.
- `WellLine.log`, `WealthLine.log`, `LifeLine.decide`/`start`, `TravelLine.plan`/`note` and `JotMemo.body`
  take `where:` (nil writes nothing, as before). A trip line takes none: its `place` is where the trip goes.
- `Hub.place`: set it for a turn and every tool's line carries it.
- `GlyphPlace` builds on the Mac too, and `GlyphPlace.here(within:)` gives a named `Where` or nil. A Mac app
  needs `NSLocationUsageDescription` (and, sandboxed, `com.apple.security.personal-information.location`).

## 0.13.0: the app's name in the top line goes home (2026-11-23)

- New `\.glyphHome` environment value (GlyphCapture): an app's shell sets it once, to go to its home
  screen. `GlyphPageHeader` and `GlyphAppMark` (so `GlyphAppHeader`) read it; `GlyphPageHeader` also
  takes `home:` directly. Unset, both draw exactly as before.
- When set, the mark and the app's name are one button, `GlyphHomeButton` (public, for an app's own
  top line): identifier `chrome.home`, label "<App>, home", hint "Goes to the home screen", 44 points
  tall at least. The page's name stays plain text; `glyph.page` stays the line's identifier and label.

## 0.12.0: tags live in data/tags (2026-11-22)

The vault's `data/domains/` moved to `data/tags/` and each tag page into its folder
(`data/tags/<x>/entity.md`); `data/domains` and `data/entities/tags` stay as links to it.
- New `TagFolders` (GlyphVault): `root(vault, old:)` is the folder to write in (`data/tags`, the old
  one in a vault not moved yet), `tag(of:)` reads the tag off a path under either name.
- GlyphTags reads and writes pages in `data/tags`; a folder with no page is no tag.
- MacHub writes memos to `data/tags`, lists tag rows from it in crm/names, and its writable,
  movable and Omega checks accept both names. CrossLink's places are `data/tags/<x>`.
- Filer's backfill reads the domain off a path under either name, and `backfill("data/domains")` walks data/tags.
- A URL listing of a link is empty (`contentsOfDirectory(at:)`, `enumerator(at:)`), so StudioDirectory
  reads a linked folder where it points (Glyph Bot's domains were empty on a moved vault), and
  Filing's index walks data/tags rather than under the link. MacHub's crm/names tag rows keep the
  path `data/entities/tags/<slug>/entity.md`, which every names reader parses.

## 0.11.0: generative UI, A2UI 1.0 drawn by GlyphCore (2026-11-22)

- GlyphCapture `A2UI`, `A2UIStream`, `A2UISurface`, `A2UIAction` and `A2UISurfaceView(surface:tint:onAction:)`: Google's
  A2UI 1.0 messages (createSurface, updateComponents, updateDataModel, deleteSurface; `{"@path"}` bindings; the
  `action` message back) drawn by our own SwiftUI on iOS and macOS, in the Glyph catalog `dev.fru.glyph/catalog/v1`
  (Basic Catalog parts plus Place, DayStrip, Chart, TodoItem, TagChip). Parts and properties: `Sources/GlyphCapture/A2UI.md`.
  Unknown parts draw nothing and are logged; children not yet arrived draw as placeholders. Five invented fixtures
  (`A2UIFixtures`), tests in `A2UITests`, a demo harness `Harness/A2UIDemo` and `scripts/a2ui-shots.sh`.
- GlyphAI `ChatPlan.a2ui` (the hub's checked messages), `Hub.understand(..., supportedCatalogIds:)` (sent per turn as
  `a2uiRendererCapabilities`) and `Hub.answer(action:surface:history:)` (POST /a2ui/action). `JSONValue` is public.
- GlyphChat: `ChatEntry.surfaces` drawn under the line, `ChatModel.onAction` and `ChatModel.act(_:)`;
  `ChatModel.lines(for:hub:app:)` puts a plan's screen on its first line. An app that asks for no catalog sees no change.

## 0.10.1: the first talk no longer crashes (2026-10-31)

- GlyphCapture `LiveDictation`: speech recognition permission is asked in `speechAuthorized()`,
  `nonisolated`, and the answer hops to the main actor before the continuation is resumed. The
  callback written inline before this was main-actor code (the class is `@MainActor`), and TCC
  invokes it on its own XPC queue, so Swift's isolation check trapped (`dispatch_assert_queue`
  inside `swift_task_isCurrentExecutor`, EXC_BREAKPOINT) on the very first talk, before a word
  was said: a fresh install and a fresh Simulator every time, in every app that opens on a chat
  with a talk button. Same hazard the audio taps already avoid by being built outside the actor.
  Check: `swift Packages/GlyphCore/scripts/permission-isolation-check.swift`.

## 0.10.0: handoffs said, done by the other app, and confirmed (2026-10-30)

- `ChatPlan.Job` carries `title` (their own words, never a title from context), `at` (the clock time the hub worked
  out) and `doing` ("Asking Time to set an alarm for 3:32 PM: Take a walk"); `ChatPlan.suggest` is the hub's one
  proactive offer. `ChatPlan.confirmed` turns Time's armed answer into "Alarm set · 3:32 PM · Take a walk".
- GlyphCapture `ChatModel.lines(for:hub:app:)`: one turn as chat lines for every app on GlyphChat. A handoff shows
  its doing line under the other app's face, runs that app's agent, and for Time leaves the request in the shared
  queue, opens `GlyphAgent.armLink(back:)` (Time comes back to the asking app) and shows "Waiting for Time" until
  Time answers; only then the confirmed card (a tap opens Time), then the offer. Never a done card before Time
  says so. Without the App Group, the request goes to Time's Chat (`glyph-time://talk`) and says so.
- `ChatEntry.agent` (another app's face beside a line) and `ChatEntry.then` (a line still going; ChatModel puts
  what it returns in its place). GlyphCapture now depends on GlyphAI.

## 0.9.0: GlyphChat, one chat screen for every Glyph app, with history (2026-10-30)

- GlyphCapture `GlyphChat` (iOS) and `ChatModel`: the family's chat screen, extracted from Glyph Time's Chat and Glyph
  Native's home (faces, thinking dots, mine capped at three lines with "More", one-line cards with Undo, `answer`
  bubbles that hold several paragraphs, `ask` bubbles that ask back, Save and Dismiss for another app's job, the talk
  button, "Type instead", "New chat", "Past chats" when the model has a `ChatLog`). Parameterized by face, tint, agent
  id and the app's `respond` closure, which gets the words and the turns before them and returns `ChatEntry` lines.
- GlyphAI `ChatPlan` for Glyph Core Intelligence (POST /understand with `surface`: kind answer, act, ask or none;
  reply, question, jobs of agent, tool, arguments, quote, instruction, handoff), `Hub.understand(surface:text:history:period:)`
  (nil when the hub or Claude is away) and `Hub.perform(_:)` (each job's GlyphAI tool with its arguments, as
  `glyphcore-report run`). A nil from `respond` shows "Can't reach Glyph right now, saved to send." and keeps the words
  (`ChatModel.pending`, `resend()`). TimeAgent gains stop_timer, pause_timer and resume_timer. GlyphVault `ChatTurn`.
  Additive.

- GlyphVault `ChatLog`: one append-only JSON-lines file per chat (`<id>.jsonl`: id, app, started, device, then lines
  with n, mine, text, short, status, who, ts; a changed line is written again, the last one wins). `save` writes only
  what changed, `chats()` lists them newest first, `archive` moves one into `archived-<YYYY-MM-DD>/` (never deleted),
  `send` puts each waiting chat whole to the hub (`PUT chats/<app>/<id>.jsonl`, merged there, so twice is once) and then
  the archive moves (`PUT chats-archive/<app>/<id>.jsonl`).
- GlyphCapture `ChatHistoryButton` and `ChatHistorySheet`: the clock top left of a Chat screen, past chats one line each
  (when, the first few words), a tap reopens one, a swipe archives it, one symbol and one line when there are none.

## 0.8.0: snoozes for Glyph Time (2026-10-30)

- GlyphVault: an alarm's "snooze" and "dismiss" lines (id, label) in the TimeLog, and `TimeLog.snoozes` (taps in a
  range), `TimeLog.snoozeDays` (the last 14 days: rang, how many snoozes) and `TimeLog.snoozeInsight` (one line when
  there is a pattern: "You snooze the 6:30 alarm most Mondays", "6:30 alarm: avg 2 snoozes, 9 min late"). `routines suggest` offers an often-snoozed alarm at the time it is really stopped.

## 0.7.2: shorter still (2026-10-30)

- `RoutineSuggest`: "4 of the last 4 weeks", one line on an iPhone SE.

## 0.7.1: a routine idea's why says no more than the card (2026-10-30)

- `RoutineSuggest`: a fixed-weekday idea's why is "Seen 3 of the last 4 weeks" (its days are already in the title line).

## 0.7.0: routines for Glyph Time (2026-10-30)

- GlyphVault `Routine` and `RoutineSuggestion`: routines as Time lines (event routine, done, routine-suggestion; the last
  line per id wins, archived never deleted), `TimeLog.routines`, `routineSuggestions`, `routineLine`; `RoutineSuggest`
  finds steady patterns in Garmin, Well and Time data with plain rules, and `glyphcore-report routines suggest
  [--dry-run]` writes them to data/apps/time/sessions/<month>.routines.jsonl. Additive.

## 0.6.0: preferences, read by every agent (2026-10-30)

- GlyphVault `OmegaFormat`: `## Preferences` in build/compass.md, one line each (`~scope`, `~strength:soft|strong`,
  `~added`, a `from:` line; `~status:proposed` waits for a yes, `~status:archived` is put away): `addPreference`,
  `archivePreference`, `preferences(_:scopes:)`, `preferenceLines`, `parsePreference`, `guessScope`;
  `OmegaCompass.preferences`, `OmegaCompassEntry.scope/strong/archived`.
- GlyphAI: each agent's instructions carry the active preferences in its scopes (`GlyphAgent.instructions(with:)`,
  `scoped`; read through the hub's `GET /omega`, kept 5 minutes); `Hub.preferenceText(for:)` is the text for the
  /understand route's `preferences` field. Omega's agent gains add_preference and archive_preference; every agent
  has propose_preference (a review card, "Save as a preference?"), so `toolkit(hub, ledger)` is an agent's tools
  plus that one (the catalog and `call` use it). Additive.

## 0.5.2: the newer agent routes on a Mac (2026-10-30)

- GlyphAI `MacHub` does the rest of the hub's routes the agents use, on the vault's files as the hub's inbox does them:
  `GET omega` and `PUT omega/<path>` (life domains only, 409 over a stale base, the Compass's earlier text kept in
  build/compass.versions), `GET crm/names`, `PUT crm/move` (only the hub's moves) and `PUT memo-undo/<stem>` (moved into
  archived-<day>, never deleted), so Omega's tools, CRM's add and update and every Undo work from `glyphcore-report run`;
  `glyphcore-report undo '<a result's undo object>'` takes one back (a restore card now carries its before and after). Additive.

## 0.5.1: the app agents finished (2026-10-30)

- GlyphAI `OmegaAgent` (add_goal, update_goal, finish_goal, add_to_compass, and rules without the model);
  `CRMAgent` adds add_record and update_record (written to the entity page, Undo) and merge_records (a "same as"
  suggestion; a name that fits several pages becomes a "Which Ken?" suggestion); Jot's notes get Undo (the hub
  archives the memo). `Done` gains `title` (the thing itself, for a one-line card) and `review` (waits for a
  yes); `Undo` gains `jotArchive`, `restore` and `crmUnmake`. GlyphVault: Glyph Omega's formats
  (`OmegaFormat.swift`, from OmegaKit) and Glyph CRM's entity page (`CRMPage.swift`, from CRMKit) moved here
  unchanged so the agents write the apps' own bytes; `CRMProposalLine` writes attribute, link and merge
  suggestions, and an "org" is CRM's "product" (it was dropped by CRM's reader). On a Mac, `MacHub` cards show
  the new Undo kinds; the routes these tools add (`omega`, `crm/names`, `crm/move`, `memo-undo`) still answer 501
  there. Additive.

- App agents on a Mac (2026-10-30): `glyphcore-report agents` lists every agent and its tools with their JSON
  argument schemas, encoded from each tool's own `parameters` (never a copy); `glyphcore-report run <agent>
  <tool> '<json>'` calls the same tool on a Mac and prints its cards. GlyphAI `MacHub.swift`: with `Hub.vault`
  set, the hub's routes the agents use (`memo`, `well`, `crm/file`) are done on the vault's files the way
  the hub's inbox does them (other routes answer 501); `Hub.hostName` names a Mac's month files. Time's
  tools queue the request in `data/apps/time/requests.<host>.jsonl` and say they wait for Time on the iPhone:
  nothing on a Mac arms it. Additive.

- App agents (2026-10-30): GlyphAI `GlyphAgent` (id, name, colour, instructions, Foundation Models tools, a
  no-model fallback) with one agent per app: `JotAgent` (new_note), `WellAgent` (log_entry), `CRMAgent`
  (propose), `TimeAgent` (request_alarm, request_reminder, start_timer); `Hub` sends through the hub's
  existing routes and keeps writes for later when it is away. GlyphVault `AppLines.swift`: the lines those
  apps write (Well entry and delete, Jot memo body, CRM suggestion, Glyph Time's request queue
  `TimeRequest`). GlyphCapture `Face.swift`: the agents' living face, moved from Glyph Studio.

- GlyphVault `Spoken.swift`: the spoken-words helpers moved out of Glyph Time unchanged (number
  words, weekdays, months, ordinals, a time of day, regex helpers; `normalize(_:dropping:)` takes the
  caller's fillers), and `Recall`: when something already happened, from how it was told (clauses with
  their day and part of the day carried forward, weekdays the ones just past, never the future, a
  question when the day had to be guessed, places said). Additive; Time forwards to it.

## 0.5.0: document filing (2026-10-29)

- GlyphVault `Scan.swift`: a document's fields from its words with no model (`ScanText.read`): type,
  domain (strong words, then the type's home, then records; whole words only), dates labelled by
  NSDataDetector (issued, due, expires, renews, period), money parsed in Swift (`ScanAmount`, exact
  strings), reference numbers kept as their last 4 (`ScanText.masked` before any model sees text), the
  name `YYYY-MM-DD Issuer Type`, the sidecar note (`kind: scan`, `entities:`, `deadlines:`), voice fixes.
- GlyphVault `Filing.swift`: the vault side of filing: `rules.json` in `data/apps/filing/`, the folder
  (`data/domains/<d>/source/files/`, a subject or tax year under it), duplicates by bytes or words, the
  note's extra keys (`sha256`, `text_sha256`, `status`, `confidence`), links (Glyph CRM ids, unknown names
  as suggestions), a dated task, key-dates, `updates.jsonl`, `records/memory/expiring.md`, the review
  queue and its board line, a log per host, undo. Every line carries the document's id.
- GlyphAI `DocumentReader.swift`: PDFKit text, Vision OCR, a compact PDF with an invisible text layer
  (searchable), the on-device model on masked text in parts, grounded (names must be in the text, dates
  among its dates). `Filer.swift`: the pipeline (file, review, accept, inbox, backfill B0/B1).
- `glyphcore-report file`: the door for shells and agents (also links GlyphAI now).

- GlyphVault `TimeEvent.rule` (optional, additive): an alarm's or reminder's repeat beyond weekly
  `days` ("d2", "h2", "m1.1"); `start` and `end` also carry a repeat's first day and last moment
  ("until Nov 27"). Older readers ignore the key.
- GlyphCapture `.talkButton(page:)`: the colour the fade behind the disc blends into, default the
  system background (`Color.talkPage`, now public). A grouped or tinted page passes its own colour,
  or a lighter band shows behind the disc (Glyph Well's grouped grey Today, family audit 2026-10-29).

- GlyphCapture `LiveDictation`: the SFSpeechRecognizer fallback's microphone tap and result handler
  are made outside the main actor too (the same audio-thread trap the analyzer's tap had, fixed in
  #26). `GLYPH_DICTATION_SELFTEST=<seconds>`: the first talk button starts real dictation once and
  prints `GLYPH-SELFTEST ... heard=...`, for checking each app on a real phone.

- GlyphCapture `LiveDictation`, fixed for real devices (Fru: "none of the microphone buttons work"):
  1. it reserves the speech locale (`AssetInventory.reserve(locale:)`) before asking for the model,
     as Glyph Jot does (iOS 26 refuses a model download for an app that hasn't reserved one: "the
     speech model couldn't be downloaded"); prefers SpeechTranscriber (usually already on the
     device), else DictationTranscriber; "Getting the speech model ready" while it downloads;
  2. the final words come after the model has finished (`onFinal`, `finishing`), not the moment
     stop is tapped: with a real model the words arrive at finalization, so they were empty;
  3. falls back to SFSpeechRecognizer, on the device only; `pause()` and `resume()`, shown on
     TalkButton (Jot's layout) and the wide DictateButton; `route` says which way it heard.
  RealSpeechTests (opt in, GLYPH_REAL_SPEECH=1) hears a `say` recording through the real model.

- GlyphCapture: dictate first. `LiveDictation` (Apple's on-device SpeechAnalyzer, live words,
  `onText` and `onFinal` callbacks for AppKit code), `DictateButton` (tap to talk, tap to stop;
  into a text binding and/or `onFinal`), `View.dictatable(_:)` (a mic at a field's trailing edge),
  `DictateButton.hostingView(onFinal:)` on macOS (an NSView, e.g. an NSAlert accessory). Tests set
  `GLYPH_DICTATION_TEXT` (or the `glyphDictationText` default) to inject what is "heard". New file only.
- GlyphCapture `DictateButton(..., wide: true)`: one long full-width button with only the mic and
  live level bars while talking (Glyph Well's forms: talk first, fields after).
- GlyphCapture `TalkButton(onFinal:)` and `View.talkButton { words in }`: the big talk button of
  Glyph Jot's iPhone app (green disc in a pale ring, mic, "Tap to talk"; while talking only a
  waveform and a red stop), pinned bottom center above the tab bar, the same in every Glyph app.
  Identifier `glyph.talk`. New file only.
- GlyphCapture `.talkButton`: an overlay that steps aside while the keyboard is up, with a bottom
  content margin that reaches scroll views inside a NavigationStack, so the last rows of a list
  and a focused text field are never covered. Its fade lets taps through.
- GlyphCapture `LiveDictation.injected`: the `-glyphDictationText` launch argument is taken as
  given (read through defaults it lost commas and apostrophes); `GLYPH_DICTATION_TEXT` still wins.

- GlyphVault: `EntityRefs` reads and adds to a note's `entities:` front matter line (permanent
  entity ids) and checks that an edit changed nothing else (`onlyEntitiesChanged`). New file only.
  Used by Glyph CRM to tag a note when a suggestion is accepted; Jot and the others can use it too.
- GlyphVault (Glyph Jot 0.7.16): `StudioObject.Kind` gains `place` and `thing` with `folder`,
  `StudioDirectory` reads all four CRM kinds and keeps an entity's permanent `id:`, `mentioned(in:kinds:)`
  and `namesakes`; `Notes.rendered` takes `entities`; writing `meta.json` also sets `people`, `tags` and
  `entities` in that recording's `notes.md` front matter.

## 0.4.0 (2026-10-28)

- GlyphVault `TimeLog`: fixing the record is a line, never a rewrite. `TimeSession.id` (its device
  and first start) names a session; `edit` lines change its project, start or end (`TimeEvent`
  gains optional `start` and `end`), `delete` and `undelete` take it out and back. `sessions`
  applies them, last word wins. Additive: old files read as before.
- Fixes: a project hidden in the same second it started stays hidden (`projects` decides by line
  order, not by the second); `span` shows "42 s" under a minute instead of "0 min".

## 0.3.0 (2026-10-27)

- GlyphVault: `TimeLog`, `TimeEvent` and `TimeSession`, Glyph Time's session format: one JSON line
  per start, name, pause, resume, nudge and stop in `<YYYY-MM>.<device>.jsonl`, each device its
  own file. `sessions` folds the lines (a start while one is open closes it), `totals` sums by
  project, `summary` writes the Markdown read for Glyph Studio, `clock` and `span` format time.
  New files only; nothing existing changed. Check: `Time/TimeLogCheck.swift`.

## 0.2.0 (2026-10-26)

- GlyphCapture: `Diarizer` finds who spoke when, on device (FluidAudio 0.17.7, Apache-2.0,
  with pyannote Community-1 models, CC-BY-4.0, downloaded once). `Transcriber.transcribe`
  takes its `turns` and splits each heard sentence where the speaker changes, by word times.
  `Waveform.peaks` reads a recording's loudness outline for drawing.
- GlyphVault: `SpeakerTurn` (cleaned and numbered `S1`, `S2`...), `Transcript.split`,
  `Transcript.name(of:)` ("Speaker 2" until named) and `talkTime`. `transcript.txt` names
  unnamed voices "Speaker N". The format is unchanged: `speaker` and `speakers` were there.

## 0.1.2 (2026-10-25)

- GlyphVault: `meta.json` gains `device`, the machine a recording was made on (the
  computer's name, `ThisDevice.name`). Optional: older files read as before, and
  `createConversation(device:)` takes another name (tests use a made-up one).

## 0.1.1 (2026-10-25)

- GlyphAI: notes keep only action items the conversation states. Placeholders the model
  writes into an empty list ("None", "N/A", "No other action items mentioned") are dropped
  from decisions and actions.

## 0.1.0 (2026-10-25)

First version, from JotCore (the vault reader Jot Studio started from).

- Products: `GlyphVault`, `GlyphCapture`, `GlyphAI`, and `GlyphCore` re-exporting all three.
- GlyphVault: the Memosa vault reader (field-for-field parity with Memosa's reader) and a
  writer in the exact format: conversations with dated slugs, meta.json, transcript.json and
  transcript.txt, notes.md, task toggles, rename, move, trash into `.memosa/trash` (never
  deletes), folders; People and Accounts notes with rename rewriting every link; links
  through aliases; suggestions; tasks across the vault; `Library` (`@Observable`) following
  the folder on disk. Golden files pin the format.
- GlyphCapture: `Recorder` (mic and the Mac's sound into one AAC .m4a, levels, pause,
  safe stop, feedable for tests), `Transcriber` (SpeechAnalyzer on the device, names as
  context, model download with progress), `Permissions`.
- GlyphAI: `Summarizer` (summary, decisions, action items with owner and due date, long calls
  in parts) and `LinkSuggester`, with Apple's on-device model.
