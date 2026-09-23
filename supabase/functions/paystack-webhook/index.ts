// POST /functions/v1/paystack-webhook
//
// Public endpoint — Paystack calls it, not the app, so there is no JWT. Deploy
// it with:
//     supabase functions deploy paystack-webhook --no-verify-jwt
//
// Authenticity comes from the HMAC-SHA512 signature Paystack puts in
// x-paystack-signature, computed over the raw request body with the secret key.
// An unsigned or mis-signed request is rejected before anything is read.
//
// This is the authoritative path: if the student pays and then kills the app
// before paystack-verify runs, the order still becomes paid because of this.
// Both paths share the same idempotent applyPaymentResult().

import {
  adminClient,
  applyPaymentResult,
  json,
  notConfigured,
  paystackSecret,
} from '../_shared/paystack.ts';

/** Constant-time comparison; avoids leaking signature bytes through timing. */
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

async function hmacSha512Hex(key: string, message: string): Promise<string> {
  const encoder = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    encoder.encode(key),
    { name: 'HMAC', hash: 'SHA-512' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'HMAC',
    cryptoKey,
    encoder.encode(message),
  );
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'METHOD_NOT_ALLOWED' }, 405);
  }

  try {
    const secret = paystackSecret();
    if (!secret) return notConfigured();

    // Must read the body as raw text: re-serialising parsed JSON would change
    // the bytes and the signature would never match.
    const rawBody = await req.text();
    const signature = req.headers.get('x-paystack-signature') ?? '';

    const expected = await hmacSha512Hex(secret, rawBody);

    if (!signature || !safeEqual(signature, expected)) {
      console.warn('paystack-webhook: rejected unsigned or invalid request');
      return json({ error: 'INVALID_SIGNATURE' }, 401);
    }

    const event = JSON.parse(rawBody);

    // Only settlement events are interesting; acknowledge the rest so Paystack
    // does not retry them.
    if (event?.event !== 'charge.success') {
      return json({ ignored: event?.event ?? 'unknown' });
    }

    const admin = adminClient();
    const result = await applyPaymentResult(admin, {
      status: event.data.status,
      reference: event.data.reference,
      amount: event.data.amount,
      currency: event.data.currency,
      gateway_response: event.data.gateway_response,
    });

    // Always 200 once the signature is valid: a non-2xx makes Paystack retry,
    // and there is nothing to retry for an unknown or already-applied reference.
    return json({ ok: true, reason: result.reason });
  } catch (err) {
    console.error('paystack-webhook failed:', err);
    // 500 here IS worth a retry — it means we failed to record a real payment.
    return json({ error: 'INTERNAL_ERROR' }, 500);
  }
});
