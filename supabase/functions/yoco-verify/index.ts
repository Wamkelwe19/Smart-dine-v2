// POST /functions/v1/yoco-verify { "reference": "<our payment reference>" }
// Yoco requires signed webhooks as the payment authority. This endpoint
// returns the persisted webhook result to the owner of the payment.

import {
  adminClient,
  corsHeaders,
  json,
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
    if (!yocoSecret()) return json({ error: 'YOCO_NOT_CONFIGURED' }, 503);

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'AUTH_REQUIRED' }, 401);

    const supabase = userClient(authHeader);
    const { data: auth } = await supabase.auth.getUser();
    const user = auth?.user;
    if (!user) return json({ error: 'AUTH_REQUIRED' }, 401);

    const { reference } = await req.json().catch(() => ({}));
    if (typeof reference !== 'string' || !reference) {
      return json({ error: 'REFERENCE_REQUIRED' }, 400);
    }

    const admin = adminClient();
    const { data: payment, error } = await admin
      .from('payments')
      .select('id, order_id, status, orders!inner(student_id)')
      .eq('provider', 'yoco')
      .eq('provider_reference', reference)
      .maybeSingle();

    if (error) throw error;
    if (!payment) return json({ error: 'UNKNOWN_REFERENCE' }, 404);

    const owner = (payment.orders as unknown as { student_id: string })
      ?.student_id;
    if (owner !== user.id) return json({ error: 'NOT_YOUR_PAYMENT' }, 403);

    const reason = payment.status === 'success'
      ? 'paid'
      : payment.status === 'failed'
      ? 'failed'
      : 'pending';
    return json({ paid: reason === 'paid', reason, order_id: payment.order_id });
  } catch (error) {
    console.error('yoco-verify failed:', error);
    return json({ error: 'INTERNAL_ERROR' }, 500);
  }
});
