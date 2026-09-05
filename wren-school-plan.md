# Wren — School

A sixth source for Wren: Brisbane Boys' College notices, ranked against one boy's year level and co-curricular list, with the dated ones turned into reminders.

Companion to `wren-build-plan.md`. Same constraints: no Mac, no backend, no push, no paid account. Mockups: `design/school/` (canvas `wren-school-news.html`).

**The aim.** Be well informed and miss nothing — which are two different problems. Missing nothing is a *deadline* problem, not a reading problem. A notice you have read is worth less than a date you have kept.

---

## 1. What is actually available

All verified live on 5 September 2026, all unauthenticated, all CORS-open.

| Source | Endpoint | What it gives |
|---|---|---|
| **Schoolbox news** | `schoolbox.bbc.qld.edu.au/news/feed/<newsHash>?topic=all` | 43 items, back to Oct 2025. **Full article HTML inline** in `<description>` |
| **Schoolbox topics** | same hash, then `/<topicId>` — `/12973` Year 4 Community, `/991` Junior School Community | The same items, **labelled by the school**. See §2a |
| **Personal calendar** | `schoolbox.bbc.qld.edu.au/calendar/export.php?export=all&event_type=&token=<calToken>` | **His actual calendar as iCal**, unauthenticated. `Sabre` VObject, `text/calendar`, ~292 KB. See §1b |
| Schoolbox images | `schoolbox.bbc.qld.edu.au/storage/image.php?hash=…` | Public, no auth. `&size=constrain200` for thumbnails |
| College events | `www.bbc.qld.edu.au/wp-json/tribe/events/v1/events?start_date=…` | 25 events as JSON, real start/end datetimes |
| Same, as iCal | `www.bbc.qld.edu.au/events/?ical=1` | `Australia/Brisbane` VTIMEZONE |
| College posts | `www.bbc.qld.edu.au/wp-json/wp/v2/posts` | 71 posts, `_fields` and category filters |
| Term dates | `www.bbc.qld.edu.au/term-dates/` | HTML only — no API |

**The Schoolbox feed is the operational one.** The WordPress side is marketing: concerts, reunions, the Art Show. Useful for the family calendar, useless for "does this affect Year 4 on Monday".

### What is closed

Article `<link>`s 302 to `id.bbc.qld.edu.au` (SSO). So do `/news`, `/calendar` and everything else on Schoolbox. Timetable, assessment, reports and — importantly — **his actual team and ensemble allocations** are all behind it. Wren can never discover that he is in Football 5B; you tell it.

This costs nothing for news, because the feed already carries the whole article body. Render notices in-app and never link out.

### The per-student calendar

`/calendar/ajax/full?start=<unix>&end=<unix>&userId=<id>` returns his personal calendar — and it is **session-gated**: it returns an opaque redirect to SSO exactly as `/news/31287` does. It answers in a browser only because that browser holds a Highlands session.

So it is out of reach, and deliberately stays that way. Replaying a school SSO session from a sideloaded app with no keychain story, against a system holding other children's data, is not a thing to build — see §12.

**The sanctioned route is worth hunting for instead.** The news feed hash `<newsHash>` is already a personal, unauthenticated token; Schoolbox exposes calendars the same way, so there is plausibly a tokenised iCal subscription URL on the calendar page — the "subscribe in your own calendar app" link. Unverified on this instance. If it exists it is the single highest-value source available: his actual timetable and fixtures, unauthenticated, and it drops straight in beside the news feeds with no new machinery.

**The token is not a general-purpose key.** Ten plausible calendar paths built from the news hash — `/calendar/feed/<hash>`, `/calendar/ical/<hash>`, `/ical/<hash>`, `.ics` variants and the rest — all returned opaque redirects to SSO. Only `/news/feed/<hash>` is whitelisted for anonymous access. So a calendar feed, if one exists, carries a *different* token on a path we have not seen, and it has to be found in the UI rather than derived.

---

## 1a. Authentication — decided, not revisited

**Wren does not sign in to anything.** Decided 5 September 2026, after looking at what signing in would actually take.

### Storing credentials, in principle

If credentials were ever needed, the only correct home is the **iOS Keychain** — entered on-device, `kSecClassGenericPassword`, no entitlement, fine on free-tier signing. Never a config file, never `project.yml`, never a GitHub Actions secret: **this repo is public**, which is what buys the free macOS runner minutes, and `.gitignore` already carries a scar from an SSH key that went in once. That distinction stands regardless of the decision below.

### Why signing in is not worth building

Highlands does not have a login form. It has **Azure AD B2C running a custom policy** (`B2C_1A_SCHOOLBOX_SIGNIN_PROD`). Posting a username and password to its `SelfAsserted` endpoint is step 5 of a multi-step orchestration and requires, per attempt: a `tx=StateProperties` transaction token, a matching `x-csrf-token`, four `x-ms-cpim-*` cookies, and the correct orchestration-step counter. A `200` there does not yield a session — it advances the state machine. Getting an actual `PHPSESSID` means following the redirect chain through `CombinedSigninAndSignup` to token issuance and back to Schoolbox.

Reimplementing that in Swift means maintaining a scraper of Microsoft's auth flow that:

- re-extracts CSRF and orchestration state from HTML and JS on every attempt,
- breaks silently whenever the school or Microsoft edits a custom policy,
- **stops working entirely the day MFA is enabled** — and a school Microsoft tenant will enable it, if it has not already,
- can only be fixed via a CI round trip, since there is no local toolchain.

That is the most fragile component imaginable, guarding data that is largely reachable another way, in an app whose whole premise is that it keeps working unattended.

### The boundary

A Highlands session reaches `/calendar/ajax/full?userId=<id>` — a per-student endpoint on a system holding other families' children's records. Automated credential replay against that is not something this project builds, whoever owns the account.

### What is allowed instead

1. **Tokenised URLs the school issues** — the news feed hash, and an iCal subscription URL if one exists. Unauthenticated by design, revocable by the school, no credential held.
2. **A value you paste into Settings** when a token changes. `SchoolSource.url` is already free text (§4), so this needs no new code — and it fails visibly rather than silently.

If a personal iCal URL turns up, it supersedes this entire question.

**It turned up. See §1b.** The sign-in analysis above still stands as the record of why Wren does not authenticate — but the thing sign-in would have been *for*, the personal calendar, is available without it.

---

## 1b. The personal calendar — the best source, and unauthenticated

Found 5 September 2026:

```
schoolbox.bbc.qld.edu.au/calendar/export.php?export=all&event_type=&token=<calToken>
```

Verified with **no cookie**: `200`, `text/calendar; charset=utf-8`, ~292 KB, generated by `Sabre VObject` (`X-WR-CALNAME: Highlands Calendar`). This is his real, personal calendar — timetable, fixtures, everything the school has put against his name — as a standard iCal feed a phone can subscribe to. It is everything `/calendar/ajax/full` was, delivered the sanctioned way.

The `token` is separate from the news hash and lives on a path guessing never reached (§1). It comes from the calendar page's "export/subscribe" affordance, so it must be **entered once, by the parent**, and stored — it is not derivable.

### It is a credential

Anyone with the URL reads his whole calendar. So it is treated exactly as §1a requires: entered in Settings, held in the **Keychain**, **never** in the repo, and it never appears in a log or a share export. `SchoolSource.url` already carries it as free text; the only addition is that a source flagged `isSecret` is Keychain-backed and redacted everywhere it is shown (`export=all&…token=<calToken>` → `token=••••`).

### Why it changes the shape of the app

News tells you what the school *announced*. This tells you what his week *actually is*. It answers "what does he have tomorrow, and what does he need for it" directly, rather than by inference from prose — which was the whole reason the deadline extractor in §7 had to exist. Extraction stays for the notices that never become calendar events (survey deadlines, "ordering is now open"), but for anything timetabled it is now a fallback, not the mechanism.

### How to consume it

- **Parse**, don't subscribe-and-forget. iOS can subscribe to an iCal URL at the OS level, but that puts events in Apple Calendar outside Wren's reach and outside the ranking. Wren fetches and parses it itself (Foundation has no iCal parser; this is a small hand-rolled `VEVENT` reader in `WrenCore`, or the one third-party exception if a dependency is ever justified — decide in Phase E).
- **Key on `UID`.** Events carry stable `UID`s (`124313/1`); dedupe and diff on them across fetches so a changed room or a cancelled period is detectable, not just additive.
- **Categorise.** Confirm from the real file (below) how his classes, whole-school events and fixtures are distinguished — `CATEGORIES`, `UID` prefix, or `X-` properties. That mapping decides what reaches Today versus what stays in a calendar view.
- **Same fetch budget as the feeds.** Foreground plus `BGAppRefreshTask`; 292 KB is fine a few times a day.

### To confirm from the file (no personal detail needs to leave the device)

- `grep -c BEGIN:VEVENT` — event count, and whether `export` values other than `all` filter it
- `grep -oE '^DTSTART[^:]*:[0-9]{8}' | sort` first/last — the date span it covers
- `grep -oE '^CATEGORIES:.*' | sort -u`, `grep -oE '^UID:[^/]*' | sort -u` — how event kinds are separated
- Fetch twice minutes apart — both `200` confirms the token is durable, not single-use

Until those are known, §9's calendar view is designed against the shape, not the contents.

### Fetch mechanics

The feed sends `Cache-Control: no-store` and **no `ETag` or `Last-Modified`** — conditional GET is not available. Dedupe on `<guid>`. `<ttl>` is 1 minute and should be ignored.

Foundation's `XMLParser` handles the RSS and `JSONDecoder` the WordPress APIs. No third-party dependency, and no scraper: the one scrape-shaped target is the term dates page, which publishes four dates a year eighteen months ahead. Hand-curate it into a bundled JSON file (§5) and re-check annually.

---

## 2. The shape of the feed

Four things drive every design decision below.

1. **The first four items are pinned**, out of date order, then it goes chronological. Sort by `pubDate`; treat original position ≤ 3 as a `isPinned` flag.
2. **`<category>` is useless.** Populated on 11 of 43 items, and only ever with `Co-curricular News` or `General Notices, Staff News, Co-curricular News`. Relevance must come from title and body text.
3. **Nearly half the feed is one series.** 19 of 43 items are `Birtles House Charity - Watoto - Day 1` … `Day 19`. Two more are byte-identical reposts of `Pipe Band Sponsorship Opportunities 2026`.
4. **Deadlines live in prose**, not in fields: *"Survey Closing Date Thursday 24 September 2026"*, *"parking on P&F Oval from 1.00pm on Monday"*, *"All interested boys will undertake a trial in Term 4"*.

---

## 2a. The topic feeds change the design

The feed URL takes a trailing topic id: `/news/feed/<hash>/12973` is *Year 4 Community*, `/991` is *Junior School Community*.

**They add no content.** Every item in both was already in `?topic=all` — Year 4 returned 1 item, Junior School 2, all three `guid`s present in the 43. `all` is the superset and the only source of history.

**What they add is the school's own classification**, and that is worth more than the content would have been.

### The case that settles it

The single most valuable item in the entire feed is `guid 31287`, titled **"Week 9 Week B"**. It is the Year 4 weekly bulletin, written by his teachers, and it contains:

- that no further homework will be set this term, and why
- the assessment schedule for weeks 9 and 10
- **"Our Prep class Assembly will be followed by a fun activity for Grade 4 and 6 — Monday College Hall 1.30pm. Y4 Dads/Significant male role model invited to attend"**
- blazers going missing at play, and where to leave them
- the full uniform, haircut and shoe standard

The whole-school notice about that same assembly says only that parking on P&F Oval closes from 1.00pm. **The time, the venue, and the fact that he is expected to bring his dad exist only in the Year 4 bulletin.**

And the relevance scorer in §4 would have ranked it near zero. The title carries no year token, no date and no activity; the body says "Year 4" once, in passing, about cereal boxes. Text matching would have buried the most important item in the feed under nineteen days of someone else's house charity.

**So: provenance first, text second.** An item that arrives via `/12973` is Year 4 relevant because the school says so.

### How to consume them

The topic feeds are a rolling window on recent items, not an archive — 1 and 2 items against 43. So they are a **labelling pass, not a source**:

1. Poll `?topic=all` for the corpus. Every notice is stored from there, keyed on `guid`.
2. Poll each topic feed and **union its label onto the already-stored items** by `guid`.
3. **Never revoke a label and never delete a stored notice because it dropped out of a feed.** Items age out of these windows constantly; disappearance carries no meaning.

This answers the reliability worry directly: the topic feeds do not need to be reliable. They are purely additive. If one is empty, slow, renumbered or withdrawn, the item is still in the store from `all` and still scored by text — you lose a label, never a notice. Wren should show which labels it has, and when each topic feed was last reachable, in `Diagnostics`.

Topic ids are opaque and must be **entered by you, with a name**, not guessed — see §4's configurability rule. Grab them from the Highlands news page as you find them.

### The weekly bulletin is a digest, not a notice

One "item" carries five unrelated topics. Rendering it as a single row wastes it, and extracting one date from 2,000 characters loses the other four things.

The body has no `<h2>`/`<h3>` — headings are `<strong>` or `<u>` runs, four of them, matching *Curriculum Spotlight – English*, *Father's Day Assembly*, *Blazers*, *Uniform, Haircuts & Presentation*. Split on the `<strong>`/`<u>` **elements**, not on `<p>` boundaries: one real heading sits inline mid-paragraph (`Uniform, Haircuts & PresentationA reminder that:`), so a paragraph-level split gets it wrong.

Each section then scores, extracts dates and offers reminders on its own. *Father's Day Assembly* becomes `Mon 7 Sep 1.30pm, College Hall — dads invited`, which is a calendar event; *Uniform, Haircuts & Presentation* is reference material with no date at all.

A weekly bulletin posted Friday afternoon previewing the coming week is also the natural spine for a "week ahead" view, and it is where the `Week 9 Week B` label in §5 comes from.

---

## 3. The organising rule: rank, never filter

A filter you cannot see is how you miss things. Every one of the 43 items stays reachable on the School screen; relevance decides **order**, not visibility. Four sections, all present:

| Section | What lands here |
|---|---|
| **Needs you** | Derived actions with a date — not notices. Checkbox rows, like any Wren task |
| **For Year 4** | Notices matching the profile: year level, section, co-curricular, house |
| **Whole school** | Uniform, transport, term dates, public holidays — relevant regardless of profile |
| **Everything else** | Collapsed. Series folded to one row (*"19 daily posts, 10 Aug – 4 Sep"*), then the remainder |

**Needs you holds tasks; the sections hold news.** Different objects, different verbs, so nothing appears twice. A notice becomes a task only when you accept it (§7).

An item carrying a date inside seven days can never sit in *Everything else*, whatever its relevance score. That override is the "miss nothing" guarantee, and it is the one rule that outranks the ranking.

---

## 4. Relevance

Three tiers, in strict order:

1. **Provenance.** A label from a topic feed (§2a). The school's own classification, and never overridden by anything below.
2. **Always-show topics.** Uniform, transport, term dates — relevant regardless of the boy.
3. **Text.** Everything the first two do not reach: the 40 items in `all` that carry no label.

Tier 3 is the fallback, not the mechanism. It was the whole design before the topic feeds turned up, and `Week 9 Week B` is the standing reminder of why it cannot be trusted alone.

The rest of this section is tier 3. It is pure date-and-string logic with no UI — `WrenCore`, fully testable. Since there is no local Swift toolchain, every test run costs a CI round trip: write the scorer **and its full test table together**, in one commit, rather than iterating.

```swift
public struct SchoolProfile: Codable, Hashable, Sendable {
    public var name: String?
    public var yearLevel: Int              // 4
    public var house: String?              // e.g. "Rowan" — changes on the move to Secondary
    public var activities: Set<String>     // e.g. ["Football", "Pipe Band", "Water Polo"]
    public var teams: Set<String>          // ["5B", "QDU 10.1"] — from notices, once known
    public var alwaysShow: Set<Topic>      // .uniform, .transport, .termDates, .fundraising
}
```

`section` is derived, not stored: Prep–6 is Junior School, 7–12 Secondary.

### Nothing about the school is compiled in

Every value above is a free-text field or an editable set, and so is everything in §1 and §5 — feed URL, events URL, school name, term dates. There is no `enum House`, no `enum Activity`, no hardcoded BBC vocabulary anywhere in `WrenCore` or the models.

This is not tidiness. The profile is a moving target on a yearly cycle: the year level increments, the house changes on the move from Junior to Secondary, teams are reallocated every season, and the co-curricular list changes whenever he picks something up or drops it. Anything baked into a Swift `enum` is a CI round trip to change — and with no local toolchain, that is the most expensive kind of edit in this project.

So the chip lists on the profile screen are **suggestions harvested from the feed**, not a fixed vocabulary: activity names accumulate from what notices actually mention, and `+ Add` takes anything. At the start of Term 1 Wren increments the year level and asks you to confirm the year and the house together, which is the one moment the profile reliably goes stale.

The same rule makes a second boy, or a second school, a data change rather than a code change.

### The rules that matter

Ordered by how badly naive matching fails them:

- **Ranges.** `"Open to all current Year 4 to Year 11 students"` must match Year 4. So must `"Years 5–8"`, `"Prep – Year 6"`, `"Junior School"`. This is the case a substring match gets wrong, and it is the single most common form in the feed.
- **Team grades.** `"Football: 10A, 10B … 5A, 5B, 5C, 5D"` — a bare `5B` is a team name. Only matches once `teams` is populated.
- **Activities.** `Debating`, `Colla Voce`, `Chess` as literal tokens. Note that one real item lists *Colla Voce* beside *Debating: QDU 10.1* — relevant for the choir, irrelevant for the Year 10 debating teams in the same sentence. Score the match, don't score the item.
- **Negatives, which demote hard.** `Class of 1976`, `Old Boys`, `boarders`, `Seniors`, `Year 12`, `Vintage Collegians`.
- **Always-relevant, regardless of profile.** Uniform, parking, buses, term dates, public holidays, weather. These bypass the year-level test entirely.

Show the reason, and show how confident it is. Every ranked row carries the tags that put it there, and the tag's fill says which tier it came from: **filled highlight means the school labelled it** (`YEAR 4 COMMUNITY`), **outline means Wren inferred it** (`YEAR 4`, `DEBATING`). One glance separates fact from guess. The notice view highlights the matched phrase **in the body text where it occurs** — see `Item.dc.html`. When it gets something wrong you can see why, which is the difference between a filter you trust and one you turn off.

### Series collapsing

Match `^(.+?)[\s–—-]+(?:Day|Part|Week|No\.?)\s*\d+$`, group by the stem, render one row with a count and a date span. Generalise the stem-stripping to trailing dates and it kills the identical reposts too.

---

## 5. The term calendar

Bundled JSON, hand-curated from the published page. Verified:

| | Term | Dates | Non-teaching days |
|---|---|---|---|
| 2026 | 3 | Tue 14 Jul – Thu 17 Sep | Show Day Wed 12 Aug; pupil-free Mon 13 Jul, **Fri 4 Sep**, Fri 18 Sep |
| 2026 | 4 | Wed 7 Oct – Wed 2 Dec | King's Birthday Mon 5 Oct; pupil-free Tue 6 Oct |
| 2027 | 1 | Thu 28 Jan – Wed 24 Mar | Year 7 starts Wed 27 Jan (camp departs) |
| 2027 | 2 | Tue 13 Apr – Thu 17 Jun | Anzac Day Sun 25 Apr; Labour Day Mon 3 May |
| 2027 | 3 | Tue 13 Jul – Thu 16 Sep | Show Day Wed 11 Aug; student-free Fri 3 Sep |
| 2027 | 4 | Wed 6 Oct – Wed 1 Dec | King's Birthday Mon 4 Oct |

This buys three things: *"Term 3 · Week 9"* as ambient context, correct relative dates (*"closes in 19 days"* spans a holiday), and the ability to resolve `"Term 4"` in prose to a real date.

### The A/B week cycle

One feed item is titled `"Week 9 Week B"` — the school runs a two-week timetable. Counting from the Term 3 start gives Week 9 = 7–11 Sep, which matches the posting date. So **Week 9 of Term 3 2026 is Week B**, and that one observation anchors the cycle.

What it does *not* settle is whether the cycle resets at each term boundary or runs continuously. Two or three more observations across a term change would confirm it. Until then, derive the label but mark it low-confidence in `Diagnostics` rather than asserting it on Today.

Worth the trouble: for a Year 4 parent, *"Week B"* answers "which kit today?" more often than any news item will.

---

## 6. Data model

```
Models/
  SchoolNotice.swift     @Model — guid (unique), title, bodyHTML, published, isPinned,
                         seriesStem, imageHashes, labels, score, matchedTags, isRead
  SchoolSection.swift    @Model — noticeGUID, ordinal, heading, bodyHTML, score
                         (a bulletin's sub-topics; one row for a plain notice)
  SchoolSource.swift     @Model — name ("Year 4 Community"), url, kind (.all/.topic/
                         .calendar/.events), isSecret, lastReachable, lastItemCount
  SchoolEvent.swift      @Model — uid (unique), title, location, start, end, allDay,
                         categories, sourceKind, correlatedNoticeGUID?
  SchoolProfile.swift    @Model — one row
  SuggestedDate.swift    @Model — sectionID?, eventUID?, proposedTitle, date,
                         sourceSentence?, confidence, state (.pending/.accepted/.dismissed)

Packages/WrenCore/Sources/WrenCore/
  SchoolRelevance.swift    labels + profile + text → score + matched tags
  SchoolSections.swift     bulletin HTML → [(heading, body)], split on strong/u runs
  SchoolDeadlines.swift    section text → [(date, sourceSentence, confidence)]
  SchoolCorrelation.swift  [notice] × [event] → merged items + confidence (§8a)
  SchoolICal.swift         iCal text → [SchoolEvent], keyed on UID
  SchoolSeries.swift       titles → series stems
  TermCalendar.swift       date → term, week, A/B, is-teaching-day
```

`labels` only ever grows. A notice is written once from `all` and thereafter enriched — never mirrored, never pruned against a feed's current contents.

`TodayItem.Kind` stays `{bin, task, bill}`. School notices do **not** enter `TodayAgenda` — the agenda is things you have committed to, not a firehose. Accepted dates become ordinary tasks and enter it that way.

---

## 7. Dates, and where they go

This is the payoff, and it needs almost no new machinery: **`Schedule.Frequency.once` already exists**, and `RecurringTask` already handles it. A school deadline is a one-off task you did not have to type.

**Extraction proposes; it never commits.** `SuggestedDate` rows land in a triage list (`Inbox.dc.html`) showing the proposed task, the date, and **the sentence the date came from** — quoted, with the date phrase highlighted. You accept or dismiss. Two reasons: the extraction will sometimes be wrong, and a wrong reminder you cannot trace is worse than no reminder.

Items with no date get an honest empty state — *"No date found"* with a `Remind in a week` fallback — rather than a fabricated one.

### Destinations

Accepting writes to any combination of three, chosen per reminder with a remembered default (`Remind.dc.html`):

| Destination | Mechanism | Why |
|---|---|---|
| **Wren task** | `RecurringTask` + `.once` | Default. Shows on Today, notifies at 7:30 |
| **Apple Reminders** | `EventKit` | **Shared lists.** The other parent sees it, and it survives Wren being reinstalled |
| **Calendar** | `EventKit` | All-day event for things that are an occasion, not a task |

EventKit needs no paid entitlement — just `NSRemindersFullAccessUsageDescription` and `NSCalendarsWriteOnlyAccessUsageDescription` in `Info.plist`. Given Wren has no sync and no backup beyond JSON export, writing to Reminders is the only way anything leaves the phone. That makes it the more valuable destination of the two, and worth building alongside the Wren task rather than after it.

---

## 8. Fetching and notifications

Foreground fetch always. Background via `BGAppRefreshTask` — `BGTaskSchedulerPermittedIdentifiers` in `Info.plist` is a plain key, no entitlement, so it survives free-tier signing. iOS decides when it fires; expect a few times a day.

So be honest about the product: **"caught up as of this morning", not "alerted within five minutes".** Nothing in this feed is minute-critical. But it means a deadline reminder is scheduled the moment the item is first seen, not the day before — you cannot count on waking up in time to schedule it later.

**Quiet by default.** Three settings, one chosen:

- *Everything new* — a notification per item. Available, not recommended.
- *Only dated things* — **default.** An item with a date inside seven days notifies; nothing else does.
- *Nothing, just the brief*

Everything else rides the existing 7:30 morning brief as one extra section, dropped entirely on mornings with nothing to say rather than printing "no school news".

**One exception may interrupt.** A notice that changes what he carries tomorrow — the real example being *"you will not be required to bring your blazers … Boaters are still required"* — fires the evening before. Uniform is the one category where being told at 7:30 the next morning is already too late.

---

## 8a. Correlating the two sources

News and calendar are combined for *reasoning*, never flattened into one list. They are different objects: a notice is an **announcement** (verb: act), an event is an **occurrence** (verb: attend). Merge them into a single scrolling feed and a recurring timetable floods it exactly the way the Watoto series would — 40 weeks of "Science, Period 3" burying the one notice that matters. So they stay distinct objects with distinct treatments, and combine only where you consume them: Today, the brief, the reminder inbox — the surfaces that already merge bins, tasks and bills.

**The real "miss nothing" win is correlation, not concatenation.** The Father's Day assembly is the proof. It is in the calendar as a timed event (1.30pm, College Hall) *and* in the news as a notice ("no parking on the oval from 1.00pm", "dads invited"). Each holds what the other lacks. Showing them as two rows is not missing-nothing — it splits one real event across two half-complete cards. The job is to recognise they are the same thing and present **one row carrying both**: the time and venue from the calendar, the parking and invitation from the news.

### The pipeline

```
fetch news + fetch calendar
      → correlate: pair a notice with an event when they are the same real-world thing
      → merge each confident pair into one item (union of fields, both sources cited)
      → rank (§3, §4) and route to Today / brief / inbox
```

`SchoolCorrelation` takes the notice set and the event set and returns merged items plus a confidence. A merged item keeps both source ids (`SchoolEvent.correlatedNoticeGUID`) so either underlying card is still openable.

### Matching signal, in order

1. **Same day** — necessary, never sufficient. A notice's extracted date (§7) against an event's `DTSTART`.
2. **Title overlap** — token-set similarity after stripping section/house words. "Father's Day Assembly" ≈ "Junior School Father's Day Special Assembly".
3. **Location or time agreement** — a venue named in the notice body ("College Hall") appearing in the event's `LOCATION`, or the notice's extracted time matching `DTSTART`'s.

Two of the three is a merge; one is a "possibly related" cross-link, not a merge.

### Fail safe toward too much, never too little

Correlation is fuzzy, so its errors must be one-directional — the same principle as rank-never-filter. **When unsure, show both.** A duplicate row is a shrug; a dropped notice is the thing the whole feature exists to prevent. So:

- Merge only on high confidence (≥ two signals). Everything else stays separate.
- A merge is **visibly a merge** — the row shows both source tags (`CALENDAR`, `JUNIOR SCHOOL COMMUNITY`) and both cards remain reachable, so a wrong merge is legible and recoverable, never a silent swallow.
- Never let a merge *remove* an item. Merging is a display-time join over two stores that each keep all their rows; it never deletes from either.

### What only exists in one source stays first-class

Most events have no matching notice (every ordinary timetabled period) and most notices have no matching event ("ordering is now open"). Those are the common case, not the exception — correlation is a bonus join on the small overlap, not a gate everything passes through. An uncorrelated event is a normal calendar row; an uncorrelated notice is a normal news row. Nothing is contingent on finding a partner.

---

## 9. Screens

`design/school/`, ten artboards on two pages.

| | |
|---|---|
| `Main` | The School screen: four sections, tags, collapsed series |
| `Dark` | Same in dark mode — rules kept, fills dropped |
| `Today` | The school strip (`Term 3 · Week 9 · Week B`) and accepted tasks in the day list |
| `Merged` | One event correlated across calendar and news, and the unsure case left as two rows (§8a) |
| `Inbox` | Suggested dates, each with its source sentence |
| `Item` | One notice, matched phrase highlighted, dates found |
| `Bulletin` | The weekly bulletin split into its five sub-topics (§2a) |
| `Remind` | The three destinations |
| `Profile` | Year level, house, co-curricular, the sources incl. the masked calendar token |
| `Brief` | The 7:30 notification, the brief's school section, and the uniform exception |

Day headers use the shipped rule-and-label treatment from `TodayView.group(_:items:isAlert:)`, not the filled band the earlier Today mockups carried.

---

## 10. Phases

**Phase A — the pipe.** Fetch, parse, `SchoolNotice` store, background refresh, and a plain reverse-chronological list with series collapsed. No scoring. This proves the only genuinely uncertain part — that the fetch and `BGAppRefreshTask` work on a sideloaded build.

**Phase B — labels and ranking.** Topic feeds and the label union first, because it is a day's work and carries most of the value. Then `SchoolSections` to split the weekly bulletin, then `SchoolProfile`, `SchoolRelevance`, the four sections and the profile screen. Text scoring is the last thing built, not the first.

**Phase C — dates.** `SchoolDeadlines`, the suggestion inbox, accepting into a `.once` task, EventKit export.

**Phase D — context.** `TermCalendar`, the Today strip, the brief section, the uniform exception.

**Phase E — the personal calendar and correlation.** The `VEVENT` parser (`SchoolICal`), the `calToken` source as a Keychain-backed secret (§1b), `UID` diffing, `SchoolCorrelation` (§8a), and a week-ahead / timetable view (§9). Sequenced last because it needs the profile, the secret-source handling and the redaction from earlier phases — but it is the highest-value source in the plan, so bring it forward the moment the token's structure is confirmed. Correlation is display-time and additive, so it lands cleanly on top of everything already built.

Phase A is worth shipping alone: a readable, de-duplicated feed with nothing behind a login is already better than the email.

---

## 11. Open questions

- **More topic feeds.** Two known: `/12973` Year 4 Community, `/991` Junior School Community. Ids are opaque and must come from the Highlands news page — do not guess them. Worth hunting for each of his own activities and his house, since a topic feed beats any amount of text matching.
- **Whether topic feeds keep history.** Both currently return only recent items, but one observation each cannot distinguish "rolling window" from "genuinely quiet topic". If they turn out to hold history, they become a second backfill source. Either way the union rule in §2a is unaffected.
- **His teams.** Needed before team-grade matching does anything, and only discoverable from a notice or from him. His house is known — and whatever it is, the Birtles charity series that dominates the feed is not his, so it belongs in *Everything else* exactly where the ranking puts it.
- **The calendar's internal structure** — the `grep`s in §1b: event count, date span, and how `CATEGORIES`/`UID` separate his classes from whole-school events from fixtures. Shapes §9's calendar view.
- **Whether `calToken` is durable or rotates.** If the school rotates it, the paste-into-Settings model (§1a) is the graceful failure: it stops returning `200`, Wren flags the source stale, you paste a fresh URL.
- **The A/B reset rule** (§5).
- **GPS fixtures**, unverified: `gpsqld.org.au` results pages appear to be backed by a `gojaro.com` service taking `clientId` / `sportName` / `term` — likely a JSON API. That is where his sport and activity fixtures would come from.
- **Feed etiquette.** No auth, no rate limit observed, no `robots.txt` restriction on `/news`. A handful of fetches a day is reasonable; do not poll on the `<ttl>` of 1 minute.

---

## 12. Non-goals

- No login to Highlands, no credential storage, no session replay, no reimplementation of the Azure B2C flow — see §1a. No use of `/calendar/ajax/full` or any other endpoint that answers only to a logged-in browser. A tokenised URL the school hands out is fine; a borrowed session or a stored password is not
- No fetching of article pages — the feed carries the body
- No inventing dates the notice does not contain
- No second child until one works (the profile is a single row for now)
