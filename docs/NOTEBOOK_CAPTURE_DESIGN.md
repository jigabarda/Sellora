# Notebook Capture — design and plan

Photograph a page of the paper notebook, check what was read, record it.

**Status: built and verified on a device.** Branch `feat/notebook-capture`, cut
from `main` at `cdcb367`. `flutter analyze` clean, 177 tests passing, full
pick → read → preview → record path exercised on the emulator. Not yet
validated against real handwriting — see
[the open question](#the-open-question).

---

## The problem this actually solves

The obvious framing — "Quick Entry, but with a camera" — is wrong, and worth
saying so before the design makes sense.

For a single small sale, a photo is *slower* than typing `2 refill`. Taking a
picture, waiting on recognition and checking a preview is more work than eleven
keystrokes. If that were the whole feature it would not be worth the megabytes.

What a photo is genuinely better at is **a page that already exists**. Shop
owners keep the notebook because the notebook works. What they do not do is
re-type yesterday's page into an app at the end of the day. So the feature is
backfill: twelve lines of a day already written down, entered in one pass, with
the owner checking rather than transcribing.

That reframing decides everything downstream. It is a page-at-a-time importer,
not a per-sale input method, which is why it lives beside Quick Entry rather
than inside it.

## Why handwriting is tractable here

General handwriting OCR on a budget Android phone, offline, is not a solved
problem, and nothing in this design pretends otherwise. What makes this case
different is that a ledger page is not prose:

```
Aug 16
Nena     2 refill    50
Tonyo    1 ice      120
Baby     3 refill    75
```

Three properties do the work:

1. **Closed vocabulary.** Names come from the ~10 customers in this business;
   items from the ~10 products. The fuzzy matcher already handles garbled
   characters against a ten-item list — that is a far easier problem than
   recognising an arbitrary word.
2. **Small integers.** Quantities are 1–10. Not free numerals.
3. **The amount is a checksum.** `2 refill 50` proves itself against a ₱25
   price. This is the important one.

The third property inverts the usual confidence problem. Character-level OCR
confidence is a number nobody can act on. "Does this line agree with your price
list?" is a verdict the owner can act on immediately.

So the parser does not try to read *well*. It tries to read **in a way that adds
up**, and holds back the lines that do not.

### What the checksum buys, concretely

It does more than validate — it disambiguates and repairs.

- **Resolves ties the text parser must decline.** `2 refill 50` is ambiguous
  between Purified (₱25) and Distilled (₱30) on text alone; Quick Entry
  correctly refuses to guess. The arithmetic settles it: 2 × 25 = 50.
- **Recovers dropped quantities.** If only `refill 50` survives recognition,
  50 ÷ 25 = 2 gives the quantity back.
- **Licenses a looser text match.** Candidate products are shortlisted at a
  threshold *below* the normal matching bar (`_looseScore = 0.34` vs
  `minimumScore = 0.6`). Anything under the normal bar is only accepted if the
  arithmetic vouches for it. A half-recognised name plus a figure that adds up
  is stronger evidence than a clean name alone.

### What it does not fix

Cursive scrawl read reliably offline on a 3–4 GB phone does not exist at a
shippable size. The honest unknown is still **whether this owner's handwriting
reads at all**, and no amount of design removes it — it is measured, not
argued. See [the open question](#the-open-question).

## Rules

**Reading never writes.** The same rule as Quick Entry, and it matters more
here because there is more to get wrong. Recognition produces a preview, the
preview is editable, and the owner's tap on *Record* is the only thing that
touches the database. This is what makes an imperfect recogniser safe to ship: a
misread line costs a glance, not a corrupted book.

**Reconciled lines start ticked; everything else starts unticked.** Every time.
The owner opting in to a doubtful line is a decision. The app opting in on their
behalf is a guess wearing a decision's clothes.

**The catalogue price wins, never the number on the page.** A mismatch is a
question to answer, not a discount to honour. If the page says ₱45 for two ₱25
refills, recording ₱45 would quietly bake a reading error into the books. The
line is flagged and the owner decides.

**Nothing is dropped silently.** Headings, totals and unreadable lines are all
shown, marked *Skipped* or *Couldn't read*. A line that vanishes is
indistinguishable from one the app never saw.

**The page's own words stay on screen.** Every tile shows the raw recognised
text under the interpretation. The owner is holding the notebook; they need
something to compare against.

**One sale per line, not one basket.** The lines have different customers.
Collapsing them would lose which refill was whose.

**A partial page still goes in.** If line 9 fails on stock, lines 1–8 are still
recorded and the failure is reported. Losing eight good lines to one bad one is
the worse outcome.

## The offline constraint, and the trap in it

Sellora ships with **no network permission**. That is the mechanism that makes
"your records never leave your phone" a fact about the APK rather than a promise
in a privacy policy, and it is non-negotiable.

ML Kit's text recogniser is genuinely on-device — the model is compiled into the
APK via `com.google.mlkit:text-recognition:16.0.1`, the *bundled* artifact, not
the `play-services-mlkit-*` variant that downloads itself.

**But it does not ship alone.** It transitively pulls
`com.google.android.datatransport:transport-backend-cct` — Google's telemetry
uploader — and *that* declares `INTERNET` and `ACCESS_NETWORK_STATE`. Verified
by merging the manifest and reading the blame report:

```
uses-permission#android.permission.INTERNET
ADDED from [com.google.android.datatransport:transport-backend-cct:2.3.3]
```

Nothing the feature needs requires either permission. They exist so ML Kit can
phone usage stats home — precisely what the zero-permission design exists to
prevent.

**Fix:** `android/app/src/release/AndroidManifest.xml` strips both with
`tools:node="remove"`. Removing the permission rather than excluding the Gradle
module keeps ML Kit's classes resolvable; the transport is written to survive
having no connectivity, so it fails quietly. Release only — `src/debug` and
`src/profile` keep `INTERNET`, which they always had, because the Flutter tool
needs it for hot reload and those builds are never shipped.

**Verified:** the merged release manifest now contains exactly one
`uses-permission`, `com.sellora.mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
— a signature-level permission the app defines for its own dynamic broadcast
receivers. It grants nothing outward and is not a network or hardware
capability.

> **This check must be re-run whenever an Android dependency is added or
> bumped.** The permission came from a third-level transitive dependency; no
> amount of reading the plugin's own manifest would have found it.
>
> ```
> $env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"
> cd android; .\gradlew.bat :app:processReleaseMainManifest
> grep uses-permission build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml
> ```

No `CAMERA` permission is needed: `image_picker` launches the system camera by
intent, and Android only enforces `CAMERA` if the app declares it. Confirmed —
it is absent from the merged manifest.

## Shape

```
image file
   ↓  TextRecogniser            (adapter — the only part that touches ML Kit)
recognised text, one row per line
   ↓  NotebookParser            (pure — no DB, no clock, no I/O)
NotebookPage { List<NotebookLine> }
   ↓  NotebookCaptureScreen     (preview, edit, select)
   ↓  owner taps Record
SaleRepository.recordSale       (one call per selected line)
```

### Files

| File | Role |
| --- | --- |
| `lib/data/text/fuzzy.dart` | Shared fuzzy matcher, **extracted from** `quick_entry_parser.dart` |
| `lib/data/notebook/notebook_line.dart` | `NotebookLine`, `NotebookPage`, `LineStatus` |
| `lib/data/notebook/notebook_parser.dart` | Text → candidate sales. Pure. The reconciliation logic. |
| `lib/data/notebook/text_recogniser.dart` | `TextRecogniser` interface + ML Kit implementation + `rowsFromBlocks` |
| `lib/features/notebook_capture/notebook_capture_screen.dart` | Pick → preview → edit → record |
| `android/app/src/release/AndroidManifest.xml` | Strips the telemetry permissions |

### Why `fuzzy.dart` was extracted rather than copied

Two matchers that disagree about whether `purifed` is `Purified 5-Gallon Refill`
would be a bug the user experiences as the app being inconsistent with itself.
Quick Entry's private helpers became the shared module; `QuickEntryParser` now
delegates to it. `rank()` is new — the notebook reader needs the whole shortlist
because the amount is what separates the candidates, and that check happens
after ranking.

**Verified behaviour-preserving:** all 20 Quick Entry parser tests pass
unchanged after the extraction, and `flutter analyze` was clean at that point.

### `rowsFromBlocks` — the non-obvious part of the adapter

ML Kit groups text into *blocks* by proximity. On a ruled ledger page the
columns are far enough apart that the name, the item and the amount frequently
land in three different blocks. Reading `result.text` straight through would
hand the parser `Nena`, `2 refill` and `50` as three separate lines — and a line
with no amount cannot be checked against anything, which throws away the one
signal the entire feature rests on.

So rows are rebuilt geometrically: fragments sharing a horizontal band belong to
the same row, sorted left-to-right within it. The band tolerance scales with
glyph height (`_bandRatio = 0.6`) rather than being a fixed pixel count — the
same page photographed closer has taller text and proportionally taller gaps, so
a fixed band would merge rows on one photo and split them on the next.

Each fragment is banded against **the previous fragment**, not against the row's
first fragment or its running mean. This is the one part of the file that was
wrong on the first attempt and was caught by a test. Handwriting sags across a
page, and on a steadily drifting row a mean lags behind the drift — it is held
back by the fragments already in the row, so the band fails on the last column,
which is usually the amount. Measuring against the nearest fragment already in
the row (which, sorted top-down, is the one before) tracks the drift instead of
fighting it.

`rowsFromBlocks` is exported specifically so it can be tested. Geometry is
exactly the kind of code that looks obviously right and is off by one band —
which is precisely what happened.

### `LineStatus`

| Status | Meaning | In the preview |
| --- | --- | --- |
| `reconciled` | qty × catalogue price == amount on the page | *Adds up*, ticked |
| `needsReview` | read something, nothing confirmed it | *Check this*, unticked |
| `unreadable` | no product identified | *Couldn't read*, not selectable |
| `ignored` | date header, column title, running total | *Skipped*, not selectable |

`Total 1250` is a sum of the page, not a sale of 1,250 things — hence
`_headingWords`, and hence a line made only of heading words being skipped
regardless of the numbers beside it.

### OCR digit repair

`50` written by hand comes back as `5O` often enough to be worth repairing
(`_confusions`: o→0, l→1, s→5, b→8 …). The repair **only runs on tokens that
already contain a real digit**, so `SO` stays the word it is and only `5O`
becomes fifty. Applying the map blindly would wreck product names.

### Customer splitting

Ledger pages put the name first with no marker word — `Nena 2 refill 50`, not
Quick Entry's `2 refill kay Nena`. So instead of looking for a separator, every
prefix (up to 2 words, for "Aling Nena") is tried and scored **jointly with the
product left behind**, and the split only wins if it beats leaving the line
whole. Scoring the customer alone would let a shop named "Ice House" swallow the
word that identifies an ice sale.

---

## What is built

- `pubspec.yaml`: `image_picker: ^1.1.2`,
  `google_mlkit_text_recognition: ^0.15.0`.
- Permission gate found, fixed and verified (above).
- `lib/data/text/fuzzy.dart` extracted; `quick_entry_parser.dart` delegates to
  it. Behaviour-preserving — all 20 Quick Entry parser tests pass unchanged.
- `notebook_line.dart`, `notebook_parser.dart`, `text_recogniser.dart`.
- `notebook_capture_screen.dart` — intro, preview, per-line editor bottom
  sheet, record bar, partial-failure reporting.
- `providers.dart`: `textRecogniserProvider`.
- `router.dart`: `business_notebook_capture` at `/business/:businessId/scan`.
- Entry points: a *Scan a notebook page instead* button on Quick Entry, and a
  *Scan a page* row under Operations in More.

### Tests

**177 passing**, `flutter analyze` clean.

- `test/notebook_parser_test.dart` (23) — the parser is pure, so this needs no
  photograph, only recognised-text fixtures. Covers both tie-breaker directions
  (`2 refill 50` → the ₱25 product, `2 refill 60` → the ₱30 one), quantity
  recovery by division, digit repair, `SO` surviving as a word, mismatch
  pricing from the catalogue rather than the page, headings and totals skipped,
  inactive products refused, customer names not swallowing the product, and a
  whole realistic page counted.
- `test/notebook_rows_test.dart` (8) — row reconstruction from hand-built
  geometry. **This one earned its place**: it caught the running-mean band bug
  described above, on a case the implementation looked obviously correct for.
- `test/screen_smoke_test.dart` — `/business/:id/scan` added to the route
  table, so it now builds in light, dark and both brand themes. No provider
  override proved necessary; the recogniser is constructed lazily and the
  screen's initial state does no recognition.

### Verified on a device

Run on the `Sellora` AVD (Android 16, 1080×2400) against the seeded database,
using a rendered ledger page pushed to the gallery. Not real handwriting — see
[the open question](#the-open-question) — but it exercises the whole path.

- **The picker opens with no permission prompt.** Logcat shows
  `START ... act=android.intent.action.GET_CONTENT typ=image/*` from
  `com.sellora.mobile`, and the system photo picker states "Sellora will only
  have access to the photos you select". Scoped per-image access; nothing was
  granted.
- **Recognition and reconciliation work end to end.** A six-line page produced
  *"4 of 6 lines added up"*: the date header and the running total marked
  *Skipped*, four sales green with their customers attached.
- **Reading never writes — confirmed, not assumed.** After the image was
  selected, seven consecutive screenshots at 1.5 s intervals were byte-for-byte
  identical: the preview sits waiting and touches nothing. Only on tapping
  *Record 4 sales* did the database go from 77 to 81 sales, one row per line,
  totalling ₱290 — exactly what the preview showed.
- **A genuine OCR miss behaved as designed.** `Mang Tonyo` was read as
  *"Wang Tonyo"*, so no customer matched — but the product and the arithmetic
  still reconciled, so the line recorded correctly with no customer instead of
  being lost. That is precisely the degradation the checksum is meant to buy.

`test/tools/inspect_device_db.dart` prints recent sales out of a database
pulled off the device, which is how the last point was checked rather than
trusted.

## What is left

**Answer [the open question](#the-open-question)** — the only thing that decides
whether this ships.

## The open question

Everything above is architecture, and architecture cannot answer the only
question that decides whether this ships: **does the owner's actual handwriting
read?**

The design is deliberately arranged so that a bad answer degrades rather than
collapses — lines that do not reconcile are held back rather than guessed, so a
poor recognition rate produces a tedious app, not a wrong one. But tedious is
still a failure if it is most lines.

To measure it: photograph ~10 real notebook pages, run them through, count what
fraction of lines come back `reconciled`.

- **~80%** → build it out, it earns its place.
- **~30%** → the pipeline is sound but ML Kit is the wrong engine for this
  handwriting. Options then are in-app digital ink (ML Kit Digital Ink reads
  pen strokes genuinely well — but strokes, not photographs, so it is a
  different feature: writing on the phone, not photographing paper), or cloud
  OCR for this one screen, which breaks the offline constraint and would need an
  explicit decision.

The parser and preview layers are worth having either way; only the recogniser
is at risk, and it sits behind a one-method interface precisely so it can be
swapped.

**Photos of real pages are the blocker here — the messier and more typical, the
more useful the result.**

## Environment notes

- **Disk was at ~3.8 GB free on C:.** Tight for Gradle plus ML Kit artifacts.
  `sellora_mobile/build` is ~0.9 GB and fully regenerable if space is needed.
- **Gradle needs `JAVA_HOME` set explicitly** in this shell; it is not on PATH:
  `$env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"`.
- Emulator AVD `Sellora` has failed to launch on low disk before, reporting
  `FATAL | Your device does not have enough disk space to run avd`.
