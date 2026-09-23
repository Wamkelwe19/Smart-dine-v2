# Supabase — schema, policies and Edge Functions

Everything the database does now lives here rather than only in the hosted
dashboard. This closes **TBD-10** in the SRS.

```
supabase/
  migrations/     ordered SQL — apply 0001 first, then in sequence
  functions/      Deno Edge Functions for the Paystack payment flow
```

## Applying the migrations

The files are written to be **idempotent**, so they are safe to run against the
existing project: they create what is missing and leave existing data alone.

**Option A — Supabase dashboard (no tooling needed)**

Open the SQL editor and paste each file in order, 0001 through 0007, running
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
supabase functions deploy paystack-initialize
supabase functions deploy paystack-verify
supabase functions deploy paystack-webhook --no-verify-jwt
```

`--no-verify-jwt` on the webhook only: Paystack calls it, not a signed-in user,
so it authenticates by HMAC signature instead of a JWT.

### Secrets

```bash
supabase secrets set PAYSTACK_SECRET_KEY=sk_test_xxxxxxxx
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are injected
by the platform — do not set them yourself.

**The Paystack secret key and the Supabase service-role key must never appear in
the Flutter app, in `env.json`, or in this repository.** They exist only as Edge
Function secrets. The service-role key bypasses RLS entirely, which is precisely
why `orders` and `payments` have no client-facing write policy: the only way to
mark an order paid is through a function holding that key.

### Register the webhook

Paystack dashboard → Settings → API Keys & Webhooks → Webhook URL:

```
https://sotsfjzdbnmrfcdifwmi.supabase.co/functions/v1/paystack-webhook
```

## Payment flow

```
app ──▶ paystack-initialize ──▶ Paystack /transaction/initialize
                                      │  amount read from the DB, not the client
        ◀── authorization_url ────────┘
app opens checkout ──▶ student pays ──▶ redirect to za.ac.ump.smartdine://payment-callback
                                   └──▶ Paystack ──▶ paystack-webhook (signed)
app ──▶ paystack-verify ──▶ Paystack /transaction/verify/:ref
                                 │  status AND amount re-checked
                                 ▼
                     orders.payment_state = 'paid'
```

Verify and webhook are both idempotent through the unique
`payments.provider_reference`; whichever lands first wins and the other is a
no-op. That is deliberate — the webhook covers the student who closes the app
mid-payment, and the verify call gives the student who does come back an
immediate answer instead of waiting on a webhook round trip.
