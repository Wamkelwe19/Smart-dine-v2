# Requirement coverage

Every requirement that `UMPSD-SRS-001` v1.0 marked **Partial** or **Not
implemented**, and where it now stands. Written so the claims can be checked
against the code rather than taken on trust.

**Verification at the time of writing:** `flutter analyze` — 0 issues.
`flutter test` — 60 passing. `flutter build web` — succeeds.

---

## Corrections to the SRS itself

Five status tags in the SRS were wrong when it was issued. They should be fixed
before resubmission, because a reader checking them will find the discrepancy.

| Req | SRS said | Was actually | Now |
|---|---|---|---|
| REQ-17 | Implemented | **Not implemented** — the sign-up form held a `_formKey` and called `validate()`, but no field had a validator, so it always returned true | Implemented |
| REQ-21 | Partial | **Not implemented** — same cause | Implemented |
| REQ-91 | Implemented | **Staff only** — the student path never called `auth.signOut()` | Implemented for both |
| REQ-66 | Partial | **Not implemented** — the counts were the literals 2, 4 and 3 | Implemented |
| REQ-15 | Partial | **Not implemented in practice** — no session check existed anywhere | Implemented |
| REQ-83 | Partial | **Implemented** — it did revert on failure; the SRS under-claimed | Implemented |

REQ-56 and REQ-57 (card number, expiry and CVV validation) are **superseded**.
The card is now collected by Yoco's hosted page, so the app never holds it.
That satisfies REQ-58 more completely than the previous validated-but-inert form
did, and removes the PCI-DSS exposure. The old implementation was also broken:
`LengthLimitingTextInputFormatter(16)` counted the dashes its own formatter
inserted, so a real 16-digit card could not be typed, and the CVV field was hard
-limited to three digits.

---

## Now closed

| Req | Requirement | Where |
|---|---|---|
| REQ-14 | Network failure in plain language, recoverable | `core/error/app_error.dart` |
| REQ-15 | Session survives restart | `features/auth/auth_gate.dart` |
| REQ-17 | Reject empty registration fields | `core/utils/formatters.dart` + `signup_screen.dart` |
| REQ-21 | Reject malformed email before the network | `Validators.email` |
| REQ-22 | Password ≥ 8 characters, stated at failure | `Validators.password` |
| REQ-23 | Reject a duplicate student/staff number specifically | `is_identifier_available` (0005) |
| REQ-30 | Never disclose whether a number is registered | `lookup_login_email` (0005) |
| REQ-32 | No diagnostic controls in the build | debug button and `print()` calls removed |
| REQ-36 | Staff may change only their own outlet's status | `staff_cafeterias` + RLS (0003, 0006) |
| REQ-41 | Sold out and withdrawn look different | `MenuItemAvailability`, `menu_item_card.dart` |
| REQ-50 | Atomic read-and-decrement | `reserve_stock` (0004) |
| REQ-51 | Release abandoned reservations | `release_expired_reservations` + pg_cron |
| REQ-52 | Cart survives a restart | `stock_reservations` is the cart |
| REQ-53 | One cart, one cafeteria | `place_order` + `CartController.spansMultipleCafeterias` |
| REQ-59 | No checkout of an empty cart | `place_order` line-count check |
| REQ-60 | Authorise through a gateway, confirm on approval | `yoco-initialize` / signed `yoco-webhook` / `yoco-verify` |
| REQ-61 | Issue a collection reference | `gen_collection_ref` (0003), `order_confirmation_screen.dart` |
| REQ-62–69 | The whole order lifecycle | 0003, 0004, `queue_tab.dart`, `orders_tab.dart` |
| REQ-74 | Reject negative price and stock | DB constraints (0001) + `Validators` |
| REQ-75 | Delete a menu item | `management_tab.dart` |
| REQ-76 | Staff cannot touch another outlet's items | RLS (0006) |
| REQ-80 | Reject > 5 MB, downscale > 1600px | `menu_item_editor.dart` |
| REQ-81 | Delete the object when replaced or removed | `deleteImageIfOwned` |
| REQ-89 | Staff notice composer | `settings_tab.dart` |
| REQ-93 | Release stock on sign-out | `release_my_reservations` |
| REQ-110 | RLS on every table | 0006 |
| REQ-111 | Sign-in lookup via a database function | 0005 |
| REQ-112 | Keys in build config, not source | `core/config/app_config.dart`, `env.json` |
| REQ-113 | Storage writes restricted to bound staff | 0007 |
| REQ-115 | No personal data in release logs | `kDebugMode` guard in `app_error.dart` |
| REQ-123 | Lints clean, no file over 800 lines | 0 issues; largest file 422 lines (was 2,123) |
| REQ-124 | Tests for cart, reservation and validation logic | 60 tests in `test/` |
| REQ-125 | Contrast, 48dp targets, screen-reader labels | `core/theme/`, `QuantityStepper`, `Semantics` |

Also closed from the TBD list: **TBD-02** (order persistence), **TBD-03** (RLS),
**TBD-04** (enumeration), **TBD-05** (key handling), **TBD-06** (reservation
model), **TBD-07** (documentation), **TBD-10** (schema in version control),
**TBD-11** (notice composer), **TBD-12** (placeholder screens), **TBD-13**
(oversized files), **TBD-14** (tests).

---

## Still open, and why

| Req | Requirement | Status |
|---|---|---|
| REQ-31 | Limit repeated failed sign-ins | **Delegated, not built.** Rate limiting belongs on the server — a client-side limit is bypassed by calling the API directly. Supabase's auth service enforces this, and `AppError` surfaces it as "Too many attempts". Worth confirming the dashboard's rate-limit settings before a pilot. |
| REQ-90 | Push notifications when backgrounded | **Not built.** This was TBD-15, left open pending a scope decision for v1.0. Notices are read in-app. |
| REQ-114 | POPIA compliance and account deletion | **Partial.** Collection is minimised and explained in the Profile tab, but deletion is a documented manual request rather than an in-app button — doing it properly needs an authenticated admin endpoint. |
| REQ-104 | One-handed use | **Improved, unverified.** Primary navigation is a bottom bar and all targets meet 48dp, but this needs the observational test the SRS describes. |
| REQ-116–122 | Correctness, usability, reliability targets | **Untested.** These require the scripted acceptance runs, the ten-participant usability test and device testing that clause 5.4 specifies. |

---

## What has not been run

Being straight about this, because it matters for a demonstration:

1. **The migrations have not been applied to a live database.** They parse
   cleanly and are written to be idempotent, but they are unverified until
   someone runs them. Apply them to a development project first if you can.
2. **The Yoco Edge Functions and webhook have not been deployed or exercised
   end to end.** Card checkout will fail until Step 4 of SETUP.md is done; cash
   checkout does not depend on it.
3. **Google sign-in has not been exercised**, and needs OAuth clients
   registered. The button hides itself until it is configured.
4. **No Android or iOS build has been produced on this machine** — there is no
   Android SDK installed here. The web target compiles, which proves the code
   is sound, but a device build should be run before the demonstration.
5. **The concurrency test in SETUP.md Step 6 is the important one.** The atomic
   reservation is the central correctness claim of this system and it deserves
   to be demonstrated with two real devices.
