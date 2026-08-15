# Smart Insights — design draft

Status: **not started.** This is a specification, not a record of work done.

The goal is an assistant that answers "what should I do about my business today?"
without a language model. Every insight is arithmetic over tables the app already
has, phrased as a sentence. It runs offline, adds nothing to the APK, works on the
cheapest phone, and — the reason this shape was chosen over an LLM — it cannot
invent a number.

## Why not an LLM

Recorded here so the decision does not get relitigated from scratch.

- **On-device** (`flutter_gemma` / llama.cpp): a usable quantised model is
  0.5–2 GB against a 52.8 MB APK, needs 3 GB+ free RAM, runs at 3–10 tokens/sec
  on mid-range hardware, and a 1–2B model is weak at exactly the arithmetic a
  bookkeeping app depends on. Play Store's 200 MB base cap also forces a
  first-launch download, which dents the offline promise the welcome screen makes.
- **Cloud** (Claude API): cheap for this workload, but requires the `INTERNET`
  permission, uploads business records, and cannot hold an API key in the client —
  a key in an APK is extractable, so it needs the server this product exists to
  avoid.
- **Neither is ruled out forever.** Ship this first; if users then ask questions
  these insights cannot answer, that is real evidence for a model rather than a
  guess.

## The one rule

**An insight that fires on thin data is as bad as a hallucinated one.** A
"you'll run out in 2 days" derived from a single sale is worse than silence,
because the user has no way to tell it apart from a well-founded one. Every rule
below therefore carries an explicit minimum-evidence gate, and the gate is part of
the rule, not an afterthought. When the gate fails, the insight does not appear —
it is never softened into a hedge.

Second rule, following from it: **every insight states its evidence.** Not
"you're losing money" but "expenses were ₱18,350 against ₱605 in sales over the
last 7 days". The number is the point; the sentence is packaging.

## Data available

No schema change is needed. Everything comes from tables that exist at v5:

| Table | Columns the rules use |
| --- | --- |
| `sales` | `business_id`, `total`, `created_at` |
| `sale_lines` | `sale_id`, `product_id`, `name`, `qty`, `unit_price` |
| `products` | `id`, `name`, `stock`, `unit`, `track_stock`, `active`, `price` |
| `stock_ledger` | `product_id`, `delta`, `reason`, `at` |
| `expenses` | `amount`, `category`, `at` |
| `refunds` | `sale_id`, `amount`, `at` |
| `customers` | `id`, `name` |

`stock_ledger` is the important one — it is the only place with a *history* of
stock movement, so it is what makes any rate-of-change rule possible.

## The rules

Ordered by how useful they are likely to be, which is also a sensible build order.
Each is one method on the repository, one row in the UI.

### 1. Stock run-out forecast

> "Distilled 5-Gallon Refill runs out in about 3 days — you're selling
> 1.4 a day and have 3 left."

Sum `stock_ledger.delta` where `reason = 'sale'` over the last 14 days per product,
divide by days observed to get a daily burn rate, divide current `stock` by that.

- Only `track_stock = 1 AND active = 1` (an untracked or delisted product cannot
  run out — this is the same rule `listLowStock` already enforces, and the two
  must not drift apart again).
- **Gate:** at least 3 separate sale days for that product and a burn rate above
  zero. A product sold once is not a trend.
- Severity by days remaining: ≤2 danger, ≤7 warning, otherwise skip entirely —
  "runs out in 40 days" is not news.

### 2. Profit direction, with the reason

> "You're ₱17,745 down over the last 7 days. Rent (₱8,000) and payroll (₱5,000)
> are most of it."

Revenue and expenses for the period, then the largest expense categories by share.
The existing `reportSummaryProvider` already computes the first half; this adds the
attribution.

- **Gate:** at least 7 days since the business was created, and at least one sale
  or expense. A business set up yesterday has no trend to report.
- Compare against the previous equal-length window to say "down from" rather than
  just stating a figure, but only when that window also has data.

### 3. Day-of-week pattern

> "Tuesdays are your slowest day — about ₱120 against ₱480 on Saturdays."

Group `sales.created_at` by weekday over the last 4–8 weeks.

- **Gate:** at least 4 occurrences of each weekday being compared, and a
  meaningful gap between best and worst (say 40%). Three Tuesdays is noise, and
  a 5% difference is not a pattern worth acting on.

### 4. Dead stock

> "Old Blue Container hasn't sold in 60 days. It's tying up ₱250."

Active products with no `sale_lines` row in N days, valued at `price * stock`.

- **Gate:** product created more than N days ago — something added last week has
  not "stopped" selling.

### 5. Refund concentration

> "3 of your last 10 Ice Tube Sack sales were refunded."

Refunds joined through `sales` → `sale_lines` to a product, as a share of that
product's sales.

- **Gate:** at least 5 sales of that product and at least 2 refunds. One refund
  out of two sales is a 50% rate and means nothing.

### 6. Quiet customers

> "Aling Nena used to buy weekly and hasn't in 3 weeks."

Customers whose gap since last purchase is well above their own historical average
gap.

- **Gate:** at least 3 prior purchases to establish a rhythm. This one is the most
  likely to feel wrong if the gate is loose — build it last.

## Shape of the code

Follows the existing layering exactly; nothing new is introduced.

```
lib/data/insights/
  insight.dart              # Insight model + InsightSeverity enum
  insights_service.dart     # one method per rule, each returning Insight?
lib/features/insights/
  insights_screen.dart      # full list, reached from More
```

```dart
enum InsightSeverity { critical, warning, info }

class Insight {
  final String id;            // stable — for dismissal later, if that is added
  final InsightSeverity severity;
  final IconData icon;
  final String title;         // "Running out of Distilled 5-Gallon Refill"
  final String detail;        // the sentence carrying the numbers
  final String? actionLabel;  // "View product"
  final String? actionRoute;
}
```

`InsightsService` takes the `Database` like every other repository, and each rule
is a separate `Future<Insight?>` so it can be tested and gated in isolation. One
`insightsProvider` family on `businessId` runs them and returns a list sorted by
severity. Reuse `IconTile` and the existing severity tones — money out is
`danger`, stock is `warning`, positive is `success`, per the guide's colour rules.

**Surfacing:** a card on the Dashboard showing the top 2, plus a full list under
More → Insights. Do not put it behind a tab; the value is in it being seen without
being asked for.

**Empty state:** a new business has nothing to say. `EmptyState` with something
honest — "Record a few sales and insights will show up here" — not a fabricated
placeholder.

## Testing

The gates are the whole feature, so they are what the tests must cover. For each
rule, at minimum:

1. **Fires** on data that clearly warrants it.
2. **Stays silent** one row below the gate — the case that matters most.
3. **Arithmetic is right** — assert the actual number in the sentence, not just
   that a sentence appeared.

`test/tools/seed_device_db.dart` already builds a business with mixed stock
states, a week of sales, six expense categories and two refunds — extend that
generator rather than writing new fixtures, and it doubles as the on-device
review path.

## Deliberately not in scope

- Dismissing or snoozing an insight (needs a table; add only if asked for).
- Notifications — the app has no background work and no notification permission.
- Anything predictive beyond linear burn rate. No seasonality, no regression.
  A straight line the user can verify in their head beats a model they cannot.

## Where this sits in the queue

Feature work still outstanding, in the guide's order: discounts + receipts
(schema v6, they share the sale write path), then rentals. Insights touches no
schema, so it can land before or between them without conflict.
