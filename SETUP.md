# UMP Smart Dine — Setup

Everything needed to get the app running from a clean checkout, in order.
Budget about 45 minutes the first time.

If you only want to run it against the existing database with cash checkout,
**Steps 1–3 are enough.** Steps 4 and 5 add card payment and Google sign-in.

---

## ⚠️ Step 0 — Rotate the Supabase keys first

The project's **secret key** and **service-role JWT** were pasted into a chat
transcript. The service-role key bypasses row level security entirely — it is
full read/write access to every table.

1. Supabase dashboard → **Project Settings → API**
2. Roll the **secret key** and the **service_role** JWT
3. Update anywhere they were used (only Edge Function secrets should hold them)

The **publishable key** (`sb_publishable_…`) is fine in the app — it is in every
compiled binary anyway. Row level security is what protects the data, which is
why Step 2 matters.

---

## Step 1 — Prerequisites

| Tool | Version | Check |
|---|---|---|
| Flutter | 3.38.4+ | `flutter --version` |
| Dart | 3.11.4+ | bundled with Flutter |
| Android Studio / Xcode | for device builds | `flutter doctor` |
| Supabase CLI | optional, for Step 2b and 4 | `supabase --version` |

```bash
flutter doctor
```

Resolve anything `flutter doctor` reports as an error before continuing.

---

## Step 2 — Database

The schema now lives in `supabase/migrations/` rather than only in the hosted
dashboard. The files are **idempotent**, so they are safe to run against the
existing project: they create what is missing and leave your data alone.

### 2a. Apply the migrations (dashboard — no tooling needed)

Open the Supabase **SQL Editor** and run each file in order, waiting for each to
finish before starting the next:

```
0001_baseline.sql              existing tables, constraints, defaults
0002_money_in_cents.sql        price_cents + sync trigger
0003_orders.sql                orders, order_items, payments, reservations
0004_stock_and_order_rpcs.sql  atomic stock + order lifecycle
0005_auth_hardening.sql        secure login lookup, profile trigger
0006_rls.sql                   row level security on every table
0007_storage_policies.sql      menu-images bucket policies
0008_specials_and_cafeteria_images.sql   specials, discounted checkout, hall photos
0009_varieties_combos_categories.sql    item options and categories
0010_repair_orders.sql         repair order schema and policies
0011_user_notifications.sql    per-user order notifications
0012_yoco_payment_provider.sql Yoco default for new card payments
```

> **0010 is what makes ordering work on the hosted project.** Its `orders` and
> `order_items` tables predate these migrations, so 0003 skipped them and every
> checkout failed with `column "payment_method" does not exist` (shown in the
> app as "Something went wrong"). 0010 repairs them in place.

Then confirm everything is in place (read-only):

```
supabase/checks/health_check.sql   every row should say OK
```

Dining-hall photos can also be bundled with the app: see
`assets/dining/README.txt` for the file naming.

### 2b. Or with the CLI

```bash
supabase link --project-ref sotsfjzdbnmrfcdifwmi
supabase db push
```

### 2c. Two manual steps that the migrations cannot do for you

**Schedule the abandoned-cart sweep.** Without this, stock reserved by a
student who closes the app is never returned.

```sql
create extension if not exists pg_cron with schema extensions;
select cron.schedule(
  'release-expired-reservations',
  '*/5 * * * *',
  $cron$ select public.release_expired_reservations(); $cron$
);
```

**Assign each staff member to a cafeteria.** This is the authorisation
boundary — a staff account can sign in and see the dashboard, but every write is
refused until a row exists here. That is deliberate: it is what stops anyone who
self-registers as staff from editing prices.

```sql
insert into public.staff_cafeterias (staff_id, cafeteria_id)
select p.id, c.id
  from public.profiles p, public.cafeterias c
 where p.student_staff_id = 'YOUR-STAFF-NUMBER'
   and c.name = 'Your Cafeteria Name';
```

> **If a staff member reports "No cafeteria assigned yet", this step is why.**

### 2d. Demo menu (optional)

`supabase/seed/seed_menu.sql` adds at least six items with photos to each of
the three halls, with flavours, sizes, one combo and one special per hall, and
a cover photo for each. It never overwrites an existing item. The photos are
already in the `menu-images` bucket under `seed/`; credits are in
`supabase/seed/images/CREDITS.md`.

### 2e. Assign staff to their cafeteria

`supabase/seed/grant_staff_access.sql` lists staff accounts and cafeterias, and
has the one-line insert to assign them. Without an assignment a staff member
sees "No cafeteria assigned yet" and gets no order notifications.

---

## Step 3 — Run the app

Configuration is injected at build time; nothing secret lives in source
(REQ-112).

```bash
cp env.example.json env.json
```

Fill in `env.json` — it is gitignored:

```json
{
  "SUPABASE_URL": "https://sotsfjzdbnmrfcdifwmi.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_...",
  "GOOGLE_WEB_CLIENT_ID": "",
  "GOOGLE_IOS_CLIENT_ID": ""
}
```

Then fetch the Flutter dependencies:

```bash
flutter pub get
```

To run without typing a command, open the project in VS Code, choose **UMP
Smart Dine** in the Run and Debug configuration selector, then press **F5**
(or choose **Run Without Debugging**). The project configuration passes
`env.json` to Flutter automatically. You can also use the VS Code play button
while `lib/main.dart` is open.

From a terminal, the equivalent command is:

```bash
flutter run --dart-define-from-file=env.json
```

> Leaving out `--dart-define-from-file` gives a clear startup error naming the
> missing keys, rather than an opaque Supabase failure on the first query.

Cash checkout works before Yoco is configured. Card checkout is available in
the app but requires the Edge Functions and Yoco secrets in Step 4.

---

## Step 4 — Card payment (Yoco)

The app uses Yoco's hosted Checkout API. The secret key is only used by
Supabase Edge Functions; the app never handles card details.

### 4a. Get test keys

In your Yoco account, open the **Checkout API integration** and select **How to
connect**. Use the test keys while developing:

- Keep the **secret** key (`sk_test_...`) for Supabase; do not put it in the app
  or `env.json`. Hosted Checkout is initialized by the server and does not need
  a public Yoco key in the Flutter build.

### 4b. Deploy the Edge Functions

```bash
supabase functions deploy yoco-initialize
```

```bash
supabase functions deploy yoco-verify
```

```bash
supabase functions deploy yoco-webhook --no-verify-jwt
```

```bash
supabase functions deploy yoco-return --no-verify-jwt
```

The initialize and verify functions require the signed-in user's JWT. The
webhook and return endpoints are public: Yoco verifies webhook requests using a
signed timestamped payload, and the return endpoint only redirects to the app.

### 4c. Store the Yoco secret

```bash
supabase secrets set YOCO_SECRET_KEY=sk_test_your_key_here
```

### 4d. Register the webhook

Register a Checkout API webhook at `https://payments.yoco.com/api/webhooks`
with the notification URL:

```
https://sotsfjzdbnmrfcdifwmi.supabase.co/functions/v1/yoco-webhook
```

Use the Yoco **test secret key** for the authenticated registration request.
Save the `secret` returned by Yoco (it starts with `whsec_`) in Supabase:

```bash
supabase secrets set YOCO_WEBHOOK_SECRET=whsec_your_webhook_secret
```

The webhook secret is shown only once. Never put either secret in the app,
`env.json`, or this repository.

### 4e. Test it

Use Yoco's test card details from the **How to connect** section in your Yoco
account. Confirm the webhook is registered and that Supabase has both secrets;
payment status is only marked paid after a valid Yoco webhook confirms the
amount and currency.

---

## Step 5 — Google sign-in

### 5a. Google Cloud

1. [console.cloud.google.com](https://console.cloud.google.com) → new project
2. **APIs & Services → OAuth consent screen** → External → fill in the basics
3. **Credentials → Create credentials → OAuth client ID → Web application**
4. Under **Authorised redirect URIs** add:
   ```
   https://sotsfjzdbnmrfcdifwmi.supabase.co/auth/v1/callback
   ```
5. Copy the **Client ID** and **Client secret**

### 5b. Supabase

**Authentication → Providers → Google** → enable, paste the client ID and
secret, save.

**Authentication → URL Configuration → Redirect URLs** → add:

```
za.ac.ump.smartdine://login-callback
```

### 5c. The app

Put the web client ID into `env.json` as `GOOGLE_WEB_CLIENT_ID`. The
"Continue with Google" button appears once it is non-empty. (The ID itself is
used by Supabase, not the app; the value only switches the button on.)

Sign-in opens in an in-app browser tab and returns to the app automatically.
The new account arrives with first name, surname, email and Google photo
filled in (migration 0011); only the student/staff number, phone and role are
asked for.

The deep-link plumbing is already in place: the `za.ac.ump.smartdine` scheme is
registered in `AndroidManifest.xml` and `Info.plist`, and PKCE is enabled in
`main.dart`.

> **First Google sign-in shows a "Finish setting up" screen.** A Google account
> has no student number and no role, and the app is built around signing in with
> that number. It is collected once; after that the user is signed in
> automatically on every launch.

---

## Step 6 — Verify

```bash
flutter analyze
```

```bash
flutter test
```

Both should be clean: **0 issues, all tests passing.**

Then walk these by hand:

| # | Check | Expected |
|---|---|---|
| 1 | Sign up, verify email, sign in | Lands on the student home screen |
| 2 | Kill the app and reopen it | Straight to home, no sign-in |
| 3 | Add an item to the cart | Stock drops by one immediately on another device |
| 4 | Two devices take the last unit at once | Exactly one succeeds; stock never goes negative |
| 5 | Add to cart, force-quit, wait 30 min | Stock returns |
| 6 | Cash checkout | Collection reference shown; order appears in the staff queue |
| 7 | Card checkout with the test card | Order shows as paid |
| 8 | Card checkout, kill app after paying | Webhook still marks it paid |
| 9 | Staff advances an order | Student sees the status change live |
| 10 | Sign in as a student, try to edit a price via the REST API | Refused by RLS |

---

## Building for release

```bash
flutter build apk --release --dart-define-from-file=env.json
```

> Release builds previously had **no network access at all** — `INTERNET` was
> declared only in the debug and profile manifests. That is fixed, but it is
> worth confirming on a real device after any manifest change.

For the Play Store you also need a real signing config; `android/app/build.gradle.kts`
still signs release with the debug keystore. Google sign-in will not work on a
release build until the release SHA-1 is registered in Google Cloud.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---| 
| `Missing build configuration: SUPABASE_URL` | Ran without the env file | Add `--dart-define-from-file=env.json` |
| Staff sees "No cafeteria assigned yet" | No `staff_cafeterias` row | Step 2c |
| "You do not have permission to do that" | RLS working as intended | Check the staff binding, or that you are signed in as the right role |
| Stock never comes back after abandoning a cart | pg_cron not scheduled | Step 2c |
| Card checkout does not open | Check the Edge Function deployment and `YOCO_SECRET_KEY` | Step 4 |
| Google button missing | `GOOGLE_WEB_CLIENT_ID` empty | Step 5c |
| Google sign-in opens the browser then hangs | Redirect URL not registered | Step 5b |
| Payment succeeds but the order stays unpaid | Webhook not registered or its signing secret is missing | Step 4d |
| Release APK cannot reach the network | Manifest missing `INTERNET` | Already fixed; rebuild |

---

## Where things live

```
lib/
  core/       config, theme tokens, error handling, formatters/validators
  data/       typed models and repositories (all Supabase access)
  features/   auth/ student/ staff/ screens
  widgets/    shared components
supabase/
  migrations/ ordered, idempotent SQL
  functions/  Yoco Checkout API Edge Functions
test/         unit tests
env.json      your local config (gitignored)
```
