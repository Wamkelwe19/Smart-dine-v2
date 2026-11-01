// POST /functions/v1/yoco-initialize { "order_id": "<uuid>" }
// The amount is read from the caller-owned order, never from the client.

import {
  YOCO_BASE,
  adminClient,
  corsHeaders,
  json,
  newReference,
  notConfigured,
  requireEnv,
  userClient,
  yocoSecret,
} from '../_shared/yoco.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'METHOD_NOT_ALLOWED' }, 405);
  }

  try {
    const secret = yocoSecret();
    if (!secret) return notConfigured();

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'AUTH_REQUIRED' }, 401);

    const supabase = userClient(authHeader);
    const { data: auth } = await supabase.auth.getUser();
    const user = auth?.user;
    if (!user) return json({ error: 'AUTH_REQUIRED' }, 401);

    const { order_id: orderId } = await req.json().catch(() => ({}));
    if (typeof orderId !== 'string' || !orderId) {
      return json({ error: 'ORDER_ID_REQUIRED' }, 400);
    }

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
    if (!order.total_cents || order.total_cents <= 0) {
      return json({ error: 'NOTHING_TO_PAY' }, 409);
    }

    const reference = newReference(order.collection_ref);
    const callbackBase = Deno.env.get('YOCO_CALLBACK_URL') ??
      `${requireEnv('SUPABASE_URL')}/functions/v1/yoco-return`;
    const callback = new URL(callbackBase);
    callback.searchParams.set('reference', reference);

    const checkoutResponse = await fetch(`${YOCO_BASE}/checkouts`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${secret}`,
        'Content-Type': 'application/json',
        'Idempotency-Key': reference,
      },
      body: JSON.stringify({
        amount: order.total_cents,
        currency: 'ZAR',
        successUrl: callback.toString(),
        cancelUrl: callback.toString(),
        failureUrl: callback.toString(),
        clientReferenceId: reference,
        externalId: order.id,
        metadata: {
          order_id: order.id,
          payment_reference: reference,
        },
      }),
    });

    const checkout = await checkoutResponse.json().catch(() => null);
    if (!checkoutResponse.ok || typeof checkout?.id !== 'string' ||
      typeof checkout?.redirectUrl !== 'string') {
      console.error('yoco-initialize: Yoco refused checkout', checkoutResponse.status);
      return json({ error: 'YOCO_INIT_FAILED' }, 502);
    }

    const admin = adminClient();
    const { error: insertError } = await admin.from('payments').insert({
      order_id: order.id,
      provider: 'yoco',
      provider_reference: reference,
      amount_cents: order.total_cents,
      currency: 'ZAR',
      status: 'pending',
      raw_response: { checkout_id: checkout.id },
    });
    if (insertError) throw insertError;

    return json({
      authorization_url: checkout.redirectUrl,
      reference,
    });
  } catch (error) {
    console.error('yoco-initialize failed:', error);
    return json({ error: 'INTERNAL_ERROR' }, 500);
  }
});
