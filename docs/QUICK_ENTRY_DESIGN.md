# Quick Entry — design

Type or say *"2 purified refill kay Aling Nena"* and land on the New Sale form
with the line and customer already filled in. Offline, no model, nothing added
to the APK.

## The rule that shapes everything: it never writes

Insights only reads. If a forecast is wrong, someone sees a bad number. Quick
Entry **writes to the ledger** — and a misparsed "2" as "20" decrements stock
wrongly, corrupts the sale record, and skews every report and insight
downstream. It is the most damaging thing in the app to get wrong.

So parsing never commits. It **pre-fills the existing form**, and the user's
own tap on that form's save button is the commit. Three consequences:

1. **No second write path.** `recordSale` and the expense insert stay the only
   ways rows are created, so their transactions, stock checks and ledger
   writes cannot drift out of sync with a parallel implementation.
2. **The parser is allowed to be wrong.** It has to be right often enough to
   save typing, not right always. A parse that fills three of four fields is a
   win, because the user was going to fill all four anyway.
3. **Anything it cannot parse costs nothing.** It opens the empty form, which
   is exactly where the user would have started.

That third point is why there is no "did you mean?" flow. Guessing twice is
worse than handing over a form.

## Why a parser rather than a model

The vocabulary is closed. Products, customers and expense categories all live
in the database, and a typical business has perhaps ten of each. This is not
open-vocabulary language understanding — it is fuzzy-matching a handful of
tokens against three short lists.

An on-device model (Gemma 3 1B via MediaPipe, ~500–600 MB, 1–3 s per command)
would handle unusual phrasing better, and unlike the Insights case that
objection is not about arithmetic, so it is a genuine option. It is deferred
rather than rejected: ship the parser, collect the utterances it fails on, and
spend the 600 MB against evidence. Swapping the parser out later touches one
class, because everything downstream of `QuickCommand` stays the same.

Cloud is ruled out for this feature specifically, not just on the offline
promise: logging a sale is what an owner does at the counter with no signal —
the exact moment a network round-trip fails them.

## What it understands

Two actions in v1, the two done daily:

| Utterance | Result |
| --- | --- |
| `2 purified refill` | Sale: 2 × Purified 5-Gallon Refill |
| `2 purified kay aling nena` | ...for customer Aling Nena |
| `dalawang ice tube` | Sale: 2 × Ice Tube Sack |
| `500 gas` | Expense: ₱500 Transport |
| `bayad kuryente 3400` | Expense: ₱3,400 Utilities |

Adding a product is deliberately out: it has six fields and is done rarely, so
the form is already the right tool.

## How the parse works

Pure function — takes the lists, returns a command. No database, no clock, no
I/O, so every case is a plain unit test.

```dart
QuickCommand parse(
  String input, {
  required List<Product> products,
  required List<Customer> customers,
});
```

1. **Normalise** — lowercase, strip punctuation, collapse whitespace.
2. **Pull the number** — digits, or a number word. Tagalog and English both
   (`dalawa`/`two`), including the `-ng`/`na` suffix Tagalog attaches when
   counting (`dalawang`).
3. **Split the customer clause** — `kay`/`para kay`/`for` splits the utterance,
   and only the right-hand side is matched against customers. Without this,
   `for` inside a product name steals the match.
4. **Score each product and each expense category** against the remaining
   tokens.
5. **Choose the intent** by which scored higher. On a tie, prefer a sale: it is
   the more frequent action, and an expense misread as a sale is caught on a
   form the user is already looking at.

### Scoring

Token-subset scoring, not edit distance over the whole string. `purified
refill` must match `Purified 5-Gallon Refill`, and whole-string Levenshtein
scores that pair badly because of the words in between. Each query token that
prefix-matches a target token counts; the score is the fraction matched,
weighted toward longer tokens so `5` alone cannot carry a match.

A minimum score is required. Below it the parser returns nothing rather than
its best guess — the same fail-closed rule the insight gates follow, for the
same reason: a confident wrong answer is worse than an admission of ignorance.

### Category synonyms

Expense categories are six fixed English words that nobody says out loud.
`gas`, `gasolina` and `fuel` all mean Transport; `kuryente`, `tubig` and
`electricity` mean Utilities. The table is small and closed because the
category list is.

## Where it lives

```
lib/data/quick_entry/
  quick_command.dart      # sealed result type
  quick_entry_parser.dart # the pure parser
lib/features/quick_entry/
  quick_entry_screen.dart # text field + live interpretation
```

A bar on the Dashboard opens the screen. As the user types, a card shows what
was understood — or says plainly that it did not understand, which is itself
useful feedback about phrasing. **Continue** opens the pre-filled form.

Voice is deliberately separable. `speech_to_text` would fill the same text
field and change nothing downstream, so it can be added later — or first, if it
turns out dictation into the existing forms is most of the win on its own.

## Testing

The parser being pure makes this cheap, so the bar is high:

1. Each supported phrasing produces the right command **with the right
   quantity** — asserting the number, not just the product.
2. Ambiguous and unknown input returns `Unparsed`, never a guess.
3. The customer clause does not swallow product tokens, and vice versa.
4. Taglish forms parse: `dalawang`, `kay`, `bayad`, `gastos`.

## Not in scope

- Editing or deleting by voice. Destructive actions from a fuzzy parse is the
  wrong risk to take, and they are rare enough that the list screens are fine.
- Multiple line items in one utterance. Possible later; the cart already
  supports it, but the phrasing gets ambiguous fast.
- Anything that writes without the user seeing a form first.
