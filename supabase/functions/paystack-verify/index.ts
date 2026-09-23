// POST /functions/v1/paystack-verify   { "reference": "ump-ABC123-1a2b3c4d" }
// -> { paid: boolean, reason: 'paid'|'already_applied'|'pending'|'failed'|
//      'amount_mismatch'|'unknown_reference', order_id?: string }
//
// 'pending' means the student has not finished on Paystack yet; the app keeps
// waiting rather than reporting a failure.
//
// This is the "come back and verify" step. The app calls it when the student
// returns from Paystack's checkout page. It never trusts what the client says
// happened — it asks Paystack directly, server to server, and re-checks the
// amount against the order before marking anything paid.
//
// The webhook is the authoritative backstop for the case where the student
// closes the app before returning. Both paths funnel through the same
// idempotent applyPaymentResult().

import {
  adminClient,
  applyPaymentResult,
  corsHeaders,
  json,
  notConfigured,
  paystackSecret,
  paystackVerify,
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

    const { reference } = await req.json().catch(() => ({}));
    if (!reference) return json({ error: 'REFERENCE_REQUIRED' }, 400);

    const admin = adminClient();

    // Confirm this reference belongs to an order owned by the caller, so one
    // student cannot probe another's payment references.
    const { data: payment, error: lookupError } = await admin
      .from('payments')
      .select('id, order_id, orders!inner(student_id)')
      .eq('provider_reference', reference)
      .maybeSingle();

    if (lookupError) throw lookupError;
    if (!payment) return json({ error: 'UNKNOWN_REFERENCE' }, 404);

    const owner = (payment.orders as unknown as { student_id: string })?.student_id;
    if (owner !== user.id) return json({ error: 'NOT_YOUR_PAYMENT' }, 403);

    const data = await paystackVerify(secret, reference);
    const result = await applyPaymentResult(admin, data);

    return json({
      paid: result.reason === 'paid' || result.reason === 'already_applied',
      reason: result.reason,
      order_id: result.orderId,
    });
  } catch (err) {
    console.error('paystack-verify failed:', err);
    return json({ error: 'INTERNAL_ERROR' }, 500);
  }
});
