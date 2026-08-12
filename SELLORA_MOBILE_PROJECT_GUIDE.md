# Sellora Mobile Project Guide

Last updated: 2026-08-06 (design system + dark mode)

## Purpose

Sellora Mobile is the Flutter, offline-first mobile clone of the Sellora web app in `../SalesManagementSystem`.

The web app is the product and design source of truth. The mobile app should reproduce the same Sellora business workflows, terminology, feature set, and visual language while using Flutter and a local SQLite database so the app can keep working without internet access.

This document exists for developers and AI agents. Read it before changing the app so future work stays aligned with the intended product path.

## Repositories

| Project | Path | Role |
| --- | --- | --- |
| Sellora web | `C:\Users\Andrei\Projects\SalesManagementSystem` | Source of truth for UX, feature behavior, business concepts, routes, and Supabase schema. |
| Sellora mobile | `C:\Users\Andrei\Projects\sellora_mobile` | Flutter implementation that clones/adapts the web app for offline mobile use. |

## Technology Direction

### Web Source App

- Next.js App Router
- React
- Tailwind/shadcn-style UI components
- Supabase auth, database, storage, RLS, and SQL migrations
- Recharts and PDF/export-related tooling

### Mobile Target App

- Flutter
- Riverpod for state/providers
- GoRouter for navigation
- SQLite through `sqflite` for all operational data
- `shared_preferences` for local session persistence
- Local auth currently uses salted SHA-256 password hashes for offline demo behavior

## North Star

Build a mobile app that feels like Sellora, behaves like Sellora, and can run Sellora's core business operations fully offline.

The mobile app is not a webview and should not depend on Supabase for core use. If cloud sync is added later, it should be layered on top of the local database model, not replace the offline-first flow.

## Non-Negotiables

1. The web app remains the source of truth for feature names, business meaning, and workflow order.
2. Core mobile workflows must work offline: login to an existing local account, switch businesses, manage products, record sales, track inventory, manage customers, record expenses/refunds, and generate reports from local data.
3. Keep business isolation strict. Operational rows must belong to one local business through `business_id`.
4. Use SQLite transactions for multi-step writes such as sales, refunds, stock adjustments, and future rental returns.
5. Inventory changes must write ledger/history rows. Do not silently change stock.
6. Mobile has its own visual identity as of 2026-08-06 — see Design System. Web
   parity now governs **features, wording, and workflow**, not pixels. Do not
   reintroduce hardcoded colours to match a web screenshot.
7. Do not introduce network/cloud dependencies unless the task explicitly asks for sync or online features.
8. If a web feature already exists, inspect the web implementation before inventing mobile behavior.
9. Clone the full mobile web flow first. Enhancements should be tracked as follow-up work and must not replace missing parity screens.

## Current Goal

We are cloning `SalesManagementSystem` into `sellora_mobile`.

The current focus is making the Flutter app follow the Sellora web app, beginning with the public landing page UI and continuing through the authenticated dashboard/business tools. The landing page should match the web mobile design: compact sticky nav, "Sellora" brand, hero copy, black primary buttons, trust badges, feature cards, three-step setup section, dark CTA band, and footer.

Clone first, enhance second. New features are allowed only after the matching web feature is already cloned or when the enhancement does not interrupt parity work. If there is a conflict between a new idea and web parity, web parity wins until the clone is complete.

## Mobile Web Parity Reference

The full mobile view of `SalesManagementSystem` has been reviewed from screenshots. Future implementation should match these screens before adding enhancements:

- Login page: vertically centered card, Sellora title, "Welcome back", email/password fields, black Sign In button, sign-up link.
- Mobile sidebar/drawer: Sellora brand, business switcher card, Menu group, Settings group, Super Admin group, Sign Out footer, blurred/dimmed page backdrop.
- Dashboard: top menu trigger, business name/subtitle, metric cards, product performance card, recent sales card, quick action card.
- Products: page title/subtitle, Categories button, Add Product button, product list table/card with search, category, price, stock, unit, status.
- Product modal: dimmed background, "Add New Product", product name, price, stock, track-stock checkbox, unit dropdown, category dropdown, optional description, Cancel/Add Product buttons.
- Customers: Add Customer button, searchable customer list, empty state with icon and Add Customer action.
- Inventory: total/low/out-of-stock metric cards, Stock Levels and Stock History tabs, stock table/list, status pill, adjust/action icon.
- Expenses: Add Expense button, expense list card, empty state with icon and Add Expense action.
- Refunds: Process Refund button, refund history card, empty state with icon.
- Reports: date range card, Generate Report button, revenue/expenses/profit/transactions cards, revenue vs expenses chart, top products table, CSV export actions.
- Settings: account profile, avatar/password controls, business profile/logo fields, team members, role permissions checkboxes for manager/employee, danger zone delete business.

These screenshots represent the current UI target for the Flutter clone. When the web source and screenshots differ, inspect the live web implementation first, then preserve the user-visible mobile layout from the screenshots as closely as Flutter allows.

## Product Flow

The intended user flow is:

1. Open app.
2. See Sellora landing page when logged out.
3. Register or log in using local auth.
4. See list of local businesses.
5. Create/select a business.
6. Enter business workspace.
7. Use dashboard, products, sales/POS, customers, inventory, expenses, refunds, reports, and future rentals/settings.
8. All data remains available offline on the device.

## Current Mobile Architecture

Important files:

- `lib/main.dart` opens SharedPreferences, opens SQLite, restores local auth, and injects providers.
- `lib/app.dart` wires the light/dark themes and the router.
- `lib/core/sellora_tokens.dart` defines design tokens, spacing, and radii.
- `lib/core/sellora_theme.dart` builds the light and dark `ThemeData`.
- `lib/core/sellora_ui.dart` holds the shared widget library.
- `lib/core/theme_controller.dart` persists the light/dark choice.
- `lib/router.dart` defines logged-out routes, business routes, and the bottom navigation shell.
- `lib/data/db/sellora_database.dart` owns the local SQLite schema and migrations.
- `lib/data/models/entities.dart` defines local operational models.
- `lib/data/repositories/*_repository.dart` owns database reads/writes.
- `lib/data/backup/backup_service.dart` exports/restores one account as JSON.
- `lib/features/settings/settings_screen.dart` is the local `/settings` equivalent.
- `lib/features/categories/categories_screen.dart` manages product categories.
- `lib/constants/product_units.dart` mirrors the web unit options.
- `lib/constants/business_types.dart` mirrors the web business type list.
- `lib/providers.dart` wires repositories and computed app data into Riverpod providers.
- `lib/features/**` contains screens and feature UI.

## Backup And Restore

Because there is no server, the local database is the only copy of the user's data
and it is deleted on uninstall or "Clear data". `/backup` (Settings -> Data ->
Backup & Restore) is the answer to that.

- Export writes a JSON envelope to the cache directory and hands it to the system
  share sheet. The user picks the destination; the app never uploads anything.
- Restore reads a file through `file_selector`, previews its row counts, then
  replaces that account's data inside a single transaction.
- The route is account-level (`/backup`, not under `/business/:id`) because one
  backup covers every business the account owns.
- `backupSchemaVersion` in `backup_service.dart` must be bumped alongside
  `SelloraDatabase._version`. Restoring a backup from a newer schema is refused.
- Delete order matters: `sale_lines` must be removed before `products` because
  `sale_lines.product_id` is ON DELETE RESTRICT. See `_deleteOrder`.
- After a restore the app signs out, because cached providers are keyed on ids
  that may no longer exist and the session may now belong to a different account.
- `test/backup_service_test.dart` covers round-trip, replace-in-place, account
  isolation, transaction rollback, and the file validation paths.

`share_plus` and `file_selector` are the only plugins added for this. Neither
declares the `INTERNET` permission, so release builds still cannot reach the
network. Verify with the merged manifest under
`build/app/intermediates/packaged_manifests/release/` after changing plugins.

## Settings

`/business/:businessId/settings` is the local counterpart to the web `/settings`
page. Reachable from the drawer ("Business Settings") and the More tab.

Implemented: Account (email read-only, editable name, change password),
Business Profile (name, type, address, phone), Data (link to Backup & Restore),
and a Danger Zone that deletes the business after the user types its exact name.

Intentional deviations from the web page, all forced by the offline model:

- **Team Members and Role Permissions are absent.** The local `users` table holds
  device accounts, not members of a shared business. There is nobody to invite
  and no server to enforce a role against. Revisit only if a local membership
  table is added (see the `tenant_users` row in Local Data Mapping).
- **Changing the password requires the current password.** The web app relies on
  an authenticated Supabase session; there is no session to lean on locally and
  the device may be shared. `changePassword` also rotates the salt.
- **No avatar or logo upload.** Both are Supabase Storage features on the web.

`BusinessRepository.delete` removes children explicitly, deepest first, in one
transaction rather than relying on ON DELETE CASCADE. A cascade from `businesses`
only survives because SQLite happens to clear `sales` (and with it `sale_lines`)
before it reaches `products`, which `sale_lines.product_id` guards with ON DELETE
RESTRICT. That ordering is an implementation detail, not a guarantee.

`businesses.type` stores the label verbatim, so a business saved under an older
type list outlives it. Use `withStoredBusinessType` when binding a stored value
to a dropdown — passing an unknown value straight to `DropdownButtonFormField`
trips its "exactly one matching item" assertion.

Covered by `test/business_repository_test.dart` and `test/auth_controller_test.dart`.

## Design System

Every screen reads from one system. There are no hardcoded colours in
`lib/features/**` — a hex literal cannot respond to the theme, which is what
left the app with two incompatible looks before.

- **Tokens** live in `sellora_tokens.dart` as a `ThemeExtension`, with a light
  and a dark palette. Read them with `context.t` (`context.t.ink`,
  `context.t.line`, `context.t.danger`...).
- **Type** comes from `context.text` (`titleSmall`, `bodyLarge`, `labelSmall`).
  The platform UI font is used throughout; serif is reserved for the `Sellora`
  wordmark via `SelloraWordmark`.
- **Spacing and radii** come from `Gap` and `Radii`. Prefer `Gap.h12` over a
  raw `SizedBox(height: 12)`.
- **The accent is indigo**, deliberately not green or red so it never competes
  with the success and danger semantics.
- **Shared widgets** in `sellora_ui.dart`: `SelloraCard`, `SectionHeader`,
  `SelloraPill`, `EmptyState`, `LoadingView`, `ErrorView`, `ButtonSpinner`,
  `DetailRow`, `SelloraSearchField`, plus `showToast` and
  `confirmDestructive`. Use these rather than rolling a local variant —
  every list screen should get the same empty state and the same search box.
- **Dark mode** is real and persisted (`theme_controller.dart`, toggled in
  Settings → Appearance). Anything new must be checked in both modes.
- **Buttons, inputs, dialogs, sheets, and snackbars** are themed centrally in
  `sellora_theme.dart`. A screen should almost never pass a `style:`.

`landing_screen.dart` carries a file-level `ignore_for_file:
prefer_const_constructors`. Nearly every widget on that page reads a token, so
it cannot be const; the ignore beats scattering per-line ignores that would go
stale. On the inverted CTA band, `t.ink` is the background and `t.canvas` the
foreground — that pair inverts correctly in both themes, where a hardcoded
white would have gone white-on-white in dark mode.

## Widget Smoke Tests

`test/screen_smoke_test.dart` boots the real app against an in-memory database
and visits every route in light mode, dark mode, and with no data at all,
failing on any exception thrown during build or layout. `test/support/
app_harness.dart` holds the setup.

Two things it depends on, both easy to get wrong:

- **All real awaits happen inside `tester.runAsync`.** sqflite talks to a real
  database over an isolate; inside `testWidgets`' fake-async zone those futures
  never complete and the test hangs with no output.
- **`settle()` alternates real time with frames** rather than calling
  `pumpAndSettle`, which never returns while an indeterminate progress
  indicator is on screen.

The surface is set to a phone size. The default 800x600 test window is not a
shape any user has, and overflows only reproduce at realistic widths.

Add a route here whenever you add one to the router — this suite is the only
automated coverage the UI has.

## Navigation

- The business shell has a bottom navigation bar **and** a drawer. The bar
  covers the four `StatefulShellRoute` branches; the drawer covers everything
  else. Before the bar existed the fourth branch (More) was unreachable —
  the drawer only mapped three.
- Tapping the active tab pops that branch back to its root.
- `errorBuilder` renders a real not-found screen; without it a stale deep link
  showed a raw GoRouter exception.
- Full-screen flows (forms, settings, backup) use `parentNavigatorKey:
  rootNavigatorKey` so they cover the bottom bar instead of nesting inside it.

## Categories

`/business/:businessId/categories`, reachable from the More tab and from a
"Categories" action in the product form. Add, rename, delete, each row showing
how many products use it. The product form has an optional category picker whose
first entry is "No category".

- Deleting a category never deletes products. `products.category_id` is ON
  DELETE SET NULL, so its products become uncategorized. The confirm dialog says
  so, with the count.
- Category names are unique per business, case-insensitively. There is no
  partial unique index for this, so the check lives in
  `CategoryRepository.nameExists` — call it before insert or rename.
- A stale `category_id` (its category deleted from another screen) falls back to
  "No category" in the picker rather than tripping the dropdown's "exactly one
  matching item" assertion.
- Writing a product invalidates `categoryUsageProvider`; the categories screen
  invalidates `productsProvider` after a delete.

Covered by `test/category_repository_test.dart`.

## Stock Tracking

Schema v4 added `products.description`, `products.unit`, and
`products.track_stock`, matching the web product form.

`track_stock` is behavioural, not cosmetic. When it is off the product has no
inventory at all — services, made-to-order items, anything that cannot run out:

- `recordSale` skips the availability check, the stock decrement, and the ledger
  row. The sale line and its revenue are still recorded in full.
- `listLowStock` excludes it; its `stock` column stays 0 forever, so it would
  otherwise appear permanently out of stock.
- The POS product picker must not gate on `stock > 0`, and the quantity stepper
  has no ceiling.
- The inventory screen filters it out entirely.

Anything new that reads `products.stock` has to ask whether `track_stock` is on
first. Covered by `test/product_stock_tracking_test.dart`.

Known deviation: web stock quantities are decimals (`parseFloat`, `step="0.01"`);
mobile stores integers. Fixing it means changing `products.stock`,
`sale_lines.qty`, and `stock_ledger.delta` together, plus every screen that
formats them — worth doing before a business sells by weight or volume.

## Database Migrations

`SelloraDatabase.migrate(db, oldVersion)` is public so `test/migration_test.dart`
can drive upgrade paths against hand-built old schemas. Every schema change
should add a case there, upgrading from each still-plausible old version — not
just the newest one.

Two traps this has already caught:

- **Do not index a column in `_createOperationalTables` that a later migration
  step adds.** That method runs for a v1 install *before* the v3 step adds
  `businesses.user_id`, so the index on it failed with "no such column" and
  bricked the upgrade. Index a column from whoever owns its table.
- **Guard ALTERs that a `CREATE TABLE` in an earlier step already covers.** The
  v4 product columns are skipped when `oldVersion < 2`, because
  `_createOperationalTables` builds `products` with them already present.

## Android Application Id

`applicationId` and `namespace` are `com.sellora.mobile`. Treat this as frozen.
It is the app's identity on Google Play and it determines the data directory
(`/data/data/com.sellora.mobile/app_flutter/sellora.db`), so changing it again
orphans every existing install's database. The launcher label is `Sellora`.

## Local Data Mapping

| Web concept/table | Mobile local equivalent | Notes |
| --- | --- | --- |
| Supabase auth users / profiles | `users` table + SharedPreferences session | Local-only auth. No Supabase dependency in mobile core. |
| `tenants` | `businesses` | Mobile uses "business" wording and `business_id`. |
| `tenant_users` | Simplified `businesses.user_id` currently | Future team/role support may need a local membership table. |
| `categories` | `categories` | Managed from the categories screen; products reference one optionally. |
| `products` | `products` | Has description/unit/track_stock as of schema v4. Mobile also keeps a SKU field the web form does not have. Stock is an integer here, a decimal on the web. |
| `customers` | `customers` | Mobile fields differ slightly; align intentionally as parity improves. |
| `sales` | `sales` | Mobile currently stores basic sale total and created timestamp. |
| `sale_items` | `sale_lines` | Mobile line items are stored locally and used for reports. |
| `inventory_logs` | `stock_ledger` | Stock changes should always create ledger entries. |
| `expenses` | `expenses` | Mobile stores amount/category/note/date-like timestamp. |
| `refunds` | `refunds` | Mobile refund support is simplified; refund items are not yet full parity. |
| Rental fields on `sales` | Not fully implemented | Required for rental business parity. |
| Role permissions | Not implemented locally | Required for owner/manager/employee parity. |

## Feature Status

| Feature | Web source | Mobile status | Target |
| --- | --- | --- | --- |
| Landing page | `src/app/page.tsx` | Implemented in Flutter with web mobile style | Keep visually aligned with web screenshots/source. |
| Register/login | `src/app/(auth)` | Implemented local auth with web-mobile-style auth cards | Continue refining copy/spacing against screenshots; keep offline session. |
| Business onboarding | `/tenants/new` | Implemented local create/select | Match web fields and business type options. |
| Dashboard | `/dashboard` | Partial, now using web-mobile-style metric cards, product performance, recent sales, and quick actions | Continue refining data parity, rental widgets, and exact spacing. |
| Products | `/products` | Field parity done — name, description, price, stock, track stock, unit, category, active; list has search, unit, low-stock, and status | Remaining: delete action, and decimal stock quantities (see Stock Tracking). |
| Categories | actions/component in web | Implemented at `/business/:businessId/categories` — add/rename/delete with product counts, plus a picker in the product form | Consider filtering the product list by category. |
| Sales/POS | `/sales`, `/sales/new` | Partial cart + stock decrement | Add discounts, notes, receipt/export, better POS flow, rental mode. |
| Customers | `/customers` | List with search, add, edit, delete | Customer purchase history still missing. |
| Inventory | `/inventory` | Partial stock levels/history | Match metric cards, tabs, table/list, status pill, manual adjustments with reasons, filters, and web-like inventory history. |
| Expenses | `/expenses` | Add, edit, delete, back-dating, running total | Date-range filtering still missing. |
| Refunds | `/refunds` | Partial | Match process/list/empty-state UI, add refund line items, status handling, stock restock behavior, sale linkage. |
| Rentals | `/rentals` and rental sale mode | Not implemented | Add rental sale creation, pending/returned/overdue states, return flow, late fees. |
| Reports | `/reports` | Range presets plus custom picker, revenue/expenses/profit, margin bar, ranked top products | CSV/PDF export still missing. |
| Settings | `/settings` | Implemented at `/business/:businessId/settings` — account, business profile, data/backup, danger zone | Team members and role permissions intentionally omitted; see the Settings section. Avatar/logo upload still missing. |
| Admin panel | `/admin` | Out of current mobile scope | Only implement if explicitly requested. |
| Backup/restore | No web equivalent | Implemented at `/backup` as JSON export via share sheet + restore via file picker | Mobile-only necessity of the offline-first model. Consider scheduled export reminders. |
| Cloud sync | Supabase-backed web | Not implemented | Optional future phase after offline model is stable. |

## Start-To-Finish Roadmap

### Phase 0 - Alignment and Foundation

- Confirm the web app is the canonical reference.
- Keep this guide updated when scope changes.
- Preserve Flutter/Riverpod/GoRouter/SQLite direction.
- Keep local database schema explicit and versioned in `SelloraDatabase`.
- Verify app builds after structural changes.

### Phase 1 - Logged-Out Experience

- Match the Sellora web landing page in Flutter.
- Match login/register screens to web styling and copy.
- Keep local account creation and local login working offline.
- Make logged-out routing clean: `/welcome`, `/login`, `/register`.

### Phase 2 - Local Business Workspace

- Support local multi-business creation, selection, switching, and deletion.
- Match the web tenant/business onboarding fields as closely as practical.
- Keep each business' data isolated by `business_id`.
- Clone the mobile web sidebar/drawer behavior before relying only on bottom navigation.
- Preserve the business switcher, menu groups, settings group, super admin group, and sign-out footer.

### Phase 3 - Core Operations MVP

- Products: list, create, edit, active state, category, unit, stock tracking.
- Sales/POS: select customer, build cart, validate stock, calculate totals, record sale, update inventory.
- Customers: create/list/edit/delete, connect sales to customers, show history.
- Inventory: low-stock visibility, stock levels, stock movement history, manual adjustments.
- For each screen, first match the web mobile layout and states shown in the parity screenshots.

### Phase 4 - Finance and Reporting

- Expenses: create/list/edit/delete, category/date filtering.
- Refunds: process refund against a sale, refund line items, status, optional restock.
- Reports: date ranges, revenue, expenses, profit, transaction count, top products.
- Add web-like charting if practical in Flutter.
- Add export capability if required by the product direction.

### Phase 5 - Web Parity Features

- Discounts: percentage/fixed discounts on sales.
- Receipts: generate/share printable receipts where feasible.
- Rentals: rental sale mode, pickup/return dates, pending/returned/overdue states, late fees.
- Settings: business profile, account info, role permissions, and local equivalents for team management.
- Role behavior: owner/manager/employee permissions if multi-user local support is required.

### Phase 6 - Polish and Reliability

- Unify visual design across authenticated screens with Sellora web styling.
- Improve empty states, loading states, validation, and error messages.
- Add delete/edit confirmations where data loss is possible.
- Add repository/unit tests for important local database operations.
- Add Flutter widget tests for critical flows if practical.
- Run formatting, analyzer, and debug build before handoff.

### Phase 7 - Optional Sync Layer

Only start this phase if explicitly requested.

- Design a local-to-cloud sync plan.
- Preserve offline-first behavior and conflict handling.
- Map local IDs to Supabase IDs carefully.
- Never make core business operations depend on an active network connection.

## Design Guidance

Use the web app and screenshots as the visual reference.

For logged-out landing/auth:

- White background, black text, restrained borders.
- Compact sticky header with Sellora, Log in, Get Started.
- Serif-like Sellora heading treatment where it matches the web mobile screenshots.
- Black filled primary buttons, subtle outlined secondary buttons.
- Feature cards with light borders and small icon tiles.
- Dark final CTA section with white text.

For authenticated tools:

- Prioritize fast scanning and repeated use.
- Use compact cards, lists, table-like rows, clear totals, and predictable actions.
- Keep cards restrained with light borders.
- Use black primary actions unless a feature-specific state requires another color.
- Do not turn operational screens into marketing pages.
- Match the mobile web spacing closely: narrow page padding, light dividers, rounded cards, small labels, strong page titles, and compact black buttons.
- Prefer modal/bottom-sheet flows only when they still visually match the web modal intent.

## Data Rules For Implementers

- Use `newLocalId(prefix)` for local IDs unless there is a clear migration reason.
- Store timestamps consistently as epoch milliseconds in SQLite.
- Every operational table should include `business_id` unless it is explicitly global/user-scoped.
- Use transactions for writes that affect multiple tables.
- Sales must validate stock before saving.
- Sales must decrement stock and create stock ledger entries.
- Manual stock edits must create stock ledger entries.
- Refunds that restock products must create stock ledger entries.
- After writes, invalidate affected Riverpod providers so screens refresh.

## AI Agent Operating Instructions

Before making feature changes:

1. Read this file.
2. Inspect the matching web route/component/action in `../SalesManagementSystem`.
3. Compare against the latest mobile web screenshots or live mobile web viewport.
4. Inspect the mobile route, provider, repository, model, and database schema.
5. Port the behavior into Flutter and SQLite instead of copying Supabase/server action assumptions.
6. Keep edits scoped to the requested feature.
7. Update this guide if the product direction, roadmap, or feature status changes.

When changing local database schema:

- Increment `_version` in `lib/data/db/sellora_database.dart`.
- Add upgrade logic for existing installs.
- Keep `onCreate` and `onUpgrade` consistent.
- Bump `backupSchemaVersion` in `lib/data/backup/backup_service.dart` to match,
  and add the new table to `_insertOrder`/`_deleteOrder` if there is one.
- Avoid destructive migrations unless explicitly approved.

When changing UI:

- Compare against the web source and the mobile screenshots.
- Keep mobile-native ergonomics, but preserve Sellora's visual identity.
- Verify text fits on narrow screens.

When finishing work:

- Run `dart format` on changed Dart files.
- Run `flutter analyze`.
- Run `flutter test` when changes touch repositories, the database, or backup.
- Run `flutter build apk --debug` when changes affect routing, database, app startup, or Android behavior.
- Report any analyzer warnings that are unrelated/pre-existing instead of hiding them.

## Definition Of Done

A feature is done when:

- It matches the web app's intent and wording unless the mobile/offline requirement justifies a clear difference.
- It works without internet.
- It stores data in the local database using the established repository/provider pattern.
- It handles empty, loading, success, validation, and error states.
- It refreshes affected screens after writes.
- It has been formatted and analyzed.
- Any intentional deviation from the web app is documented.

## Immediate Next Best Work

The next useful development path is:

1. Sale discounts (percentage/fixed) and a shareable receipt. Both touch the
   sale schema, so plan them together as schema v5.
3. Bring Customers, Inventory, Expenses, Refunds, Reports, and Settings to screenshot-level mobile web parity.
4. Add missing web parity features: discounts, rentals, settings, roles, receipt/export support.
5. Only after parity is stable, add enhancements that improve offline mobile use.
6. Harden local database migrations and add focused tests around sale/stock/refund flows.
