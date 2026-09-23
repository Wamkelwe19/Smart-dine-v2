// POST /functions/v1/paystack-initialize   { "order_id": "<uuid>" }
// -> { authorization_url, reference }
//
// Requires the caller's JWT. The amount is read from the order in the database,
// never from the request body: a tampered client cannot ask to pay less than
// the order is worth.
//
// Works for any unpaid order the caller owns, so a student can pay by card
// later from Orders (e.g. after first choosing cash, or after an abandoned
// attempt). Each attempt gets a fresh reference.

import {
  PAYSTACK_BASE,
  adminClient,
  corsHeaders,
  json,
  newReference,
  notConfigured,
  paystackSecret,
  requireEnv,
  userClient,
} from '../_shared/paystack.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const secret = paystackSecret();
    if (!secret) return notConfigured();

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'AUTH_REQUIRED' }, 401);

    const supabase = userClient(authHeader);
    const { data: auth } = await supabase.auth.getUser();
    const user = auth?.user;
    if (!user) return json({ error: 'AUTH_REQUIRED' }, 401);
    if (!user.email) return json({ error: 'EMAIL_REQUIRED' }, 400);

    const { order_id: orderId } = await req.json().catch(() => ({}));
    if (!orderId) return json({ error: 'ORDER_ID_REQUIRED' }, 400);

    // Read through the caller's own client so RLS confirms ownership for us.
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('id, student_id, total_cents, payment_state, status, collection_ref')
      .eq('id', orderId)
      .maybeSingle();

    if (orderError) throw orderError;
    if (!order) return json({ error: 'ORDER_NOT_FOUND' }, 404);
    if (order.student_id !== user.id) return json({ error: 'NOT_YOUR_ORDER' }, 403);
    if (order.payment_state === 'paid') return json({ error: 'ALREADY_PAID' }, 409);
    if (order.status === 'cancelled') return json({ error: 'ORDER_CANCELLED' }, 409);
    // Paystack refuses a zero-value charge; a free order needs no payment.
    if (!order.total_cents || order.total_cents <= 0) {
      return json({ error: 'NOTHING_TO_PAY' }, 409);
    }

    const reference = newReference(order.collection_ref);

    // Paystack only accepts an http(s) callback. paystack-return bounces the
    // browser back into the app with the reference.
    const callbackUrl = Deno.env.get('PAYMENT_CALLBACK_URL') ??
      `${requireEnv('SUPABASE_URL')}/functions/v1/paystack-return`;

    const res = await fetch(`${PAYSTACK_BASE}/transaction/initialize`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${secret}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: user.email,
        amount: order.total_cents, // already the minor unit, as Paystack expects
        currency: 'ZAR',
        reference,
        callback_url: callbackUrl,
        metadata: {
          order_id: order.id,
          collection_ref: order.collection_ref,
          student_id: user.id,
        },
      }),
    });

    const body = await res.json().catch(() => null);
    if (!res.ok || !body?.status) {
      console.error('paystack-initialize: Paystack refused', res.status, body);
      return json(
        { error: 'PAYSTACK_INIT_FAILED', detail: body?.message ?? 'unknown' },
        502,
      );
    }

    // Written with the service role: `payments` has no client insert policy.
    const admin = adminClient();
    const { error: insertError } = await admin.from('payments').insert({
      order_id: order.id,
      provider: 'paystack',
      provider_reference: reference,
      amount_cents: order.total_cents,
      currency: 'ZAR',
      status: 'pending',
    });

    if (insertError) throw insertError;

    return json({
      authorization_url: body.data.authorization_url,
      reference,
    });
  } catch (err) {
    console.error('paystack-initialize failed:', err);
    return json({ error: 'INTERNAL_ERROR' }, 500);
  }
});
