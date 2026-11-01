# Supabase — schema, policies and Edge Functions

Everything the database does now lives here rather than only in the hosted
dashboard. This closes **TBD-10** in the SRS.

```
supabase/
  migrations/     ordered SQL — apply 0001 first, then in sequence
  functions/      Deno Edge Functions for the Yoco Checkout API payment flow
```

## Applying the migrations

The files are written to be **idempotent**, so they are safe to run against the
existing project: they create what is missing and leave existing data alone.

**Option A — Supabase dashboard (no tooling needed)**

Open the SQL editor and paste each file in order, 0001 through 0012, running
each one before moving to the next.

**Option B — Supabase CLI**

```bash
supabase link --project-ref sotsfjzdbnmrfcdifwmi
supabase db push
```

### What each migration does

| File | Purpose |
|---|---|
| `0001_baseline.sql` | Captures the four existing tables in version control; normalises the nullable-boolean defaults the client disagreed about; adds the non-negative price/stock constraints (REQ-74). |
| `0002_money_in_cents.sql` | Adds `price_cents`; keeps `price` in sync by trigger during rollout. |
| `0003_orders.sql` | `orders`, `order_items`, `payments`, `stock_reservations`, `staff_cafeterias` (TBD-02). |
| `0004_stock_and_order_rpcs.sql` | Atomic stock functions and the order lifecycle (REQ-50, 51, 53, 62–64, 69). |
| `0005_auth_hardening.sql` | Closes the login enumeration oracle (REQ-111, REQ-30); profile creation trigger. |
| `0006_rls.sql` | Row level security on every table (REQ-110, REQ-76). |
| `0007_storage_policies.sql` | Locks the `menu-images` bucket to bound staff (REQ-113). |
| `0008_specials_and_cafeteria_images.sql` | Specials and discounts charged at checkout; hall cover photos. |
| `0009_varieties_combos_categories.sql` | Flavours/sizes with their own stock, combos built from items, category tabs. |
| `0010_repair_orders.sql` | Repairs the hosted project's older `orders` / `order_items` tables; removes the old insecure `place_order`. |
| `0011_user_notifications.sql` | Order-status notifications per user; Google profile details; `ensure_profile()`. |
| `0012_yoco_payment_provider.sql` | Sets Yoco as the default provider for new card-payment rows. |

### Two manual steps after migrating

**1. Schedule the reservation sweep** (REQ-51). Run once in the SQL editor:

```sql
create extension if not exists pg_cron with schema extensions;
select cron.schedule(
  'release-expired-reservations',
  '*/5 * * * *',
  $cron$ select public.release_expired_reservations(); $cron$
);
```

**2. Bind each staff member to their cafeteria.** This is the authorisation
boundary — a staff account can see the staff UI but cannot change anything until
a row exists here. It is deliberately an administrative act with no app path:

```sql
insert into public.staff_cafeterias (staff_id, cafeteria_id)
select p.id, c.id
  from public.profiles p, public.cafeterias c
 where p.student_staff_id = 'STAFF-NUMBER-HERE'
   and c.name = 'Cafeteria Name Here';
```

> Without this, staff sign in and find every write refused. That is the intended
> behaviour, not a bug — it is what stops anyone who self-registers as staff from
> editing prices.

## Edge Functions

```bash
supabase functions deploy yoco-initialize
supabase functions deploy yoco-verify
supabase functions deploy yoco-webhook --no-verify-jwt
supabase functions deploy yoco-return --no-verify-jwt
```

Only the webhook and return functions are public. The webhook validates Yoco's
HMAC signature and timestamp; the return function only redirects to the app.

### Secrets

```bash
supabase secrets set YOCO_SECRET_KEY=sk_test_xxxxxxxx
supabase secrets set YOCO_WEBHOOK_SECRET=whsec_xxxxxxxx
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are injected
by the platform — do not set them yourself.

**The Yoco secret key, webhook signing secret, and Supabase service-role key must never appear in
the Flutter app, in `env.json`, or in this repository.** They exist only as Edge
Function secrets. The service-role key bypasses RLS entirely, which is precisely
why `orders` and `payments` have no client-facing write policy: the only way to
mark an order paid is through a function holding that key.

### Register the webhook

Register a Checkout API webhook using the test secret key:

```
POST https://payments.yoco.com/api/webhooks
Authorization: Bearer sk_test_...
Content-Type: application/json

{"name":"UMP Smart Dine","url":"https://sotsfjzdbnmrfcdifwmi.supabase.co/functions/v1/yoco-webhook"}
```

Store the returned `secret` in Supabase as `YOCO_WEBHOOK_SECRET`. Yoco returns
this value only once.

## Payment flow

```
app ──▶ yoco-initialize ──▶ Yoco POST /api/checkouts
                                  │ amount read from the owned order
        ◀── redirectUrl ─────────┘
app opens hosted checkout ──▶ student pays
                               ├──▶ yoco-return redirects to the app
                               └──▶ Yoco ──▶ yoco-webhook (signed)
app ──▶ yoco-verify ──▶ checks persisted webhook result
                             │ signature, amount and currency re-checked
                             ▼
                 orders.payment_state = 'paid'
```

The signed webhook is authoritative; the browser redirect never marks an order
paid. Yoco's `checkoutId` webhook metadata maps each event to its pending
payment, and amount and currency are checked against the stored order amount.
