// Yoco Checkout API helpers. Secret keys are Edge Function secrets only.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';

export const YOCO_BASE = 'https://payments.yoco.com/api';

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

export function yocoSecret(): string | null {
  return Deno.env.get('YOCO_SECRET_KEY') || null;
}

export const notConfigured = () =>
  json({ error: 'YOCO_NOT_CONFIGURED' }, 503);

export function adminClient(): SupabaseClient {
  return createClient(
    requireEnv('SUPABASE_URL'),
    requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
    { auth: { persistSession: false } },
  );
}

export function userClient(authHeader: string): SupabaseClient {
  return createClient(
    requireEnv('SUPABASE_URL'),
    requireEnv('SUPABASE_ANON_KEY'),
    {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } },
    },
  );
}

export function newReference(collectionRef: string): string {
  const safeRef = collectionRef.replace(/[^A-Za-z0-9]/g, '');
  return `ump-${safeRef}-${crypto.randomUUID().slice(0, 8)}`;
}

export interface YocoPaymentPayload {
  id: string;
  type: string;
  status: string;
  amount: number;
  currency: string;
  metadata?: Record<string, unknown> | null;
}

export type PaymentResultReason =
  | 'paid'
  | 'already_applied'
  | 'failed'
  | 'pending'
  | 'amount_mismatch'
  | 'unknown_reference';

export async function applyYocoPaymentResult(
  admin: SupabaseClient,
  checkoutId: string,
  payload: YocoPaymentPayload,
  succeeded: boolean,
): Promise<{ reason: PaymentResultReason; orderId?: string }> {
  const { data: payment, error } = await admin
    .from('payments')
    .select('id, order_id, amount_cents, currency, status')
    .eq('provider', 'yoco')
    .filter('raw_response->>checkout_id', 'eq', checkoutId)
    .maybeSingle();

  if (error) throw error;
  if (!payment) return { reason: 'unknown_reference' };

  if (payment.status === 'success') {
    return { reason: 'already_applied', orderId: payment.order_id };
  }

  const now = new Date().toISOString();
  const validAmount = payload.amount === payment.amount_cents &&
    payload.currency === payment.currency;

  if (succeeded && !validAmount) {
    const { error: mismatchError } = await admin
      .from('payments')
      .update({
        status: 'failed',
        raw_response: { ...payload, checkout_id: checkoutId },
        verified_at: now,
      })
      .eq('id', payment.id)
      .neq('status', 'success');
    if (mismatchError) throw mismatchError;
    return { reason: 'amount_mismatch', orderId: payment.order_id };
  }

  if (!succeeded && !validAmount) {
    console.error('yoco payment.failed webhook amount/currency mismatch');
  }

  const { error: paymentError } = await admin
    .from('payments')
    .update({
      status: succeeded ? 'success' : 'failed',
      raw_response: { ...payload, checkout_id: checkoutId },
      verified_at: now,
    })
    .eq('id', payment.id)
    .neq('status', 'success');
  if (paymentError) throw paymentError;

  const { error: orderError } = await admin
    .from('orders')
    .update(
      succeeded
        ? { payment_state: 'paid', payment_method: 'card' }
        : { payment_state: 'failed' },
    )
    .eq('id', payment.order_id)
    .neq('payment_state', 'paid');
  if (orderError) throw orderError;

  return {
    reason: succeeded ? 'paid' : 'failed',
    orderId: payment.order_id,
  };
}
