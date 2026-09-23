// Shared helpers for the Paystack functions.
//
// PAYSTACK_SECRET_KEY lives in Edge Function secrets and is never sent to the
// client. Set it with:
//   supabase secrets set PAYSTACK_SECRET_KEY=sk_test_xxx --project-ref <ref>
//
// SUPABASE_SERVICE_ROLE_KEY is injected automatically by the platform. It
// bypasses RLS, which is exactly why payment writes happen here and nowhere
// else: `payments` and `orders` have no client-facing write policy at all.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';

export const PAYSTACK_BASE = 'https://api.paystack.co';

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-paystack-signature',
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

/**
 * The Paystack secret, or null while card payments have not been set up.
 * Callers answer 503 PAYSTACK_NOT_CONFIGURED, which the app shows as "Card
 * payment isn't available yet" — not a crash reported as a 500.
 */
export function paystackSecret(): string | null {
  return Deno.env.get('PAYSTACK_SECRET_KEY') || null;
}

export const notConfigured = () =>
  json({ error: 'PAYSTACK_NOT_CONFIGURED' }, 503);

/** Service-role client. Bypasses RLS — use only for payment bookkeeping. */
export function adminClient(): SupabaseClient {
  return createClient(
    requireEnv('SUPABASE_URL'),
    requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
    { auth: { persistSession: false } },
  );
}

/** Client scoped to the caller's JWT, so RLS still applies to their reads. */
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

/**
 * A fresh reference per attempt. Paystack accepts only letters, digits and
 * `-`, `.`, `=` in a reference, so no underscores.
 */
export function newReference(collectionRef: string): string {
  const safeRef = collectionRef.replace(/[^A-Za-z0-9]/g, '');
  return `ump-${safeRef}-${crypto.randomUUID().slice(0, 8)}`;
}

export interface PaystackVerifyData {
  status: string;
  reference: string;
  amount: number;
  currency: string;
  gateway_response?: string;
}

export async function paystackVerify(
  secret: string,
  reference: string,
): Promise<PaystackVerifyData> {
  const res = await fetch(
    `${PAYSTACK_BASE}/transaction/verify/${encodeURIComponent(reference)}`,
    { headers: { Authorization: `Bearer ${secret}` } },
  );

  const body = await res.json();
  if (!res.ok || !body?.status) {
    throw new Error(body?.message ?? 'Paystack verification request failed');
  }
  return body.data as PaystackVerifyData;
}

/** Paystack transaction statuses that are final and unsuccessful. */
const FAILED_STATUSES = new Set(['failed', 'reversed']);

export type PaymentResultReason =
  | 'paid'
  | 'already_applied'
  | 'failed'
  | 'pending'
  | 'amount_mismatch'
  | 'unknown_reference';

/**
 * Applies a verified Paystack result to the order.
 *
 * Idempotent: `payments.provider_reference` is unique, and a payment already
 * marked `success` short-circuits. This is what lets the verify call and the
 * webhook both fire — whichever arrives first wins and the other is a no-op.
 *
 * Only a final result changes anything. A transaction the student has not
 * finished yet (Paystack reports `abandoned`, `ongoing`, `pending`...) stays
 * pending: the old version marked those `failed` the moment the app checked,
 * which told students their payment failed before they had typed their card.
 *
 * The amount is re-checked against the order here rather than trusted from the
 * client, so a tampered client that initialised a cheaper transaction cannot
 * mark an expensive order paid.
 */
export async function applyPaymentResult(
  admin: SupabaseClient,
  data: PaystackVerifyData,
): Promise<{ applied: boolean; reason: PaymentResultReason; orderId?: string }> {
  const { data: payment, error } = await admin
    .from('payments')
    .select('id, order_id, amount_cents, status')
    .eq('provider_reference', data.reference)
    .maybeSingle();

  if (error) throw error;
  if (!payment) return { applied: false, reason: 'unknown_reference' };

  if (payment.status === 'success') {
    return { applied: false, reason: 'already_applied', orderId: payment.order_id };
  }

  const succeeded = data.status === 'success';
  const failed = FAILED_STATUSES.has(data.status);

  if (!succeeded && !failed) {
    return { applied: false, reason: 'pending', orderId: payment.order_id };
  }

  const now = new Date().toISOString();

  if (succeeded && data.amount !== payment.amount_cents) {
    const { error: mismatchError } = await admin
      .from('payments')
      .update({ status: 'failed', raw_response: data, verified_at: now })
      .eq('id', payment.id);
    if (mismatchError) throw mismatchError;
    return { applied: false, reason: 'amount_mismatch', orderId: payment.order_id };
  }

  const { error: paymentError } = await admin
    .from('payments')
    .update({
      status: succeeded ? 'success' : 'failed',
      raw_response: data,
      verified_at: now,
    })
    .eq('id', payment.id);
  if (paymentError) throw paymentError;

  // A cash order paid by card afterwards becomes a card order.
  const { error: orderError } = await admin
    .from('orders')
    .update(
      succeeded
        ? { payment_state: 'paid', payment_method: 'card' }
        : { payment_state: 'failed' },
    )
    .eq('id', payment.order_id);
  if (orderError) throw orderError;

  return {
    applied: true,
    reason: succeeded ? 'paid' : 'failed',
    orderId: payment.order_id,
  };
}
