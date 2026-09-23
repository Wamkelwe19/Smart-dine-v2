# UMP Smart Dine

A campus cafeteria pre-ordering app for the University of Mpumalanga. Students
see live menus and stock, build an order, choose how to pay and collect without
queuing. Cafeteria staff maintain their menu, control whether their outlet is
trading, and work the order queue.

Built with Flutter and Supabase. Specified by `UMPSD-SRS-001` v1.0.

**→ [SETUP.md](SETUP.md) to get it running.**

---

## What it does

**For students**

- Sign in with a student number, or with Google
- Browse each campus outlet's live menu — prices, photos and real stock counts
- Search every cafeteria's menu at once
- Build a cart; stock is reserved the moment an item goes in
- Check out with cash at the counter or by card
- Track an order from *new* through *preparing* and *ready* to *collected*
- Read notices from the cafeterias

**For staff**

- Add, edit and remove menu items, with photographs
- Set prices, stock counts and whether an item is on sale
- Open and close the outlet for orders
- Work a live queue of real orders, matched by collection reference
- Publish notices to students or to other staff

---

## How it is put together

```
lib/
  core/       config, design tokens, error handling, formatters and validators
  data/       typed models and repositories — all Supabase access lives here
  features/   auth/ · student/ · staff/
  widgets/    shared components
supabase/
  migrations/ the schema, in order, under version control
  functions/  Paystack Edge Functions (Deno)
test/         60 unit tests
```

### Three decisions worth knowing about

**Stock is reserved, not just counted.** Adding an item to a cart decrements
the stored count immediately, through an atomic database function rather than a
read-then-write from the client. Two students racing for the last unit cannot
both win. A reservation carries an owner and a 30-minute expiry, so a cart that
is abandoned releases its stock instead of holding it hostage.

**The app cannot be trusted, and is not.** Row level security is on for every
table. Students may read menus and write only their own orders; staff may write
only to a cafeteria they are bound to through `staff_cafeterias`. Order status
transitions and stock movements happen in `SECURITY DEFINER` functions, so a
modified client cannot move an order backwards or invent stock.

**The app never touches a card number.** Payment goes through Paystack's hosted
checkout. Our own Edge Function then verifies the transaction server-to-server
and re-checks the amount against the order before anything is marked paid, with
a signed webhook as the authoritative backstop if the student closes the app
mid-payment.

---

## Running it

```bash
flutter run --dart-define-from-file=env.json
```

Configuration is injected at build time and `env.json` is gitignored — see
[SETUP.md](SETUP.md).

```bash
flutter analyze
```

```bash
flutter test
```

---

## Status against the specification

The SRS tracks 129 numbered requirements. This build closes the order
persistence gap (TBD-02), row level security (TBD-03), the login enumeration
exposure (TBD-04), key handling (TBD-05), the stock reservation model (TBD-06),
schema version control (TBD-10), the notice composer (TBD-11), the placeholder
screens (TBD-12) and the test coverage gap (TBD-14).

Known gaps, honestly stated:

- **Card payment needs Paystack test keys** and the Edge Functions deployed
  before it does anything. Cash checkout works without them.
- **Google sign-in needs OAuth clients registered.** The button hides itself
  until `GOOGLE_WEB_CLIENT_ID` is set.
- **Release signing is still the debug keystore.** Google sign-in will not work
  on a release build until a real keystore exists and its SHA-1 is registered.
- **The migrations have not been run against a live database yet.** They are
  written to be idempotent and safe, but they are unverified until someone
  applies them.
- **Push notification delivery (REQ-90) is not built** — it was left open as
  TBD-15 pending a scope decision.

---

## The team

Tebogo Maremane (231112009) · Tshegofatso Masete (220477868) ·
Wamkelwe Mkhabela (230822770)

School of Computing & Mathematical Sciences, University of Mpumalanga.
Mentor: Mr C. Ndlovu.
