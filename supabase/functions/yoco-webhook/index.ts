// Public webhook. Deploy with --no-verify-jwt; authenticity is checked using
// the Yoco webhook subscription secret, timestamp, ID, and raw request body.

import {
  adminClient,
  applyYocoPaymentResult,
  json,
  notConfigured,
} from '../_shared/yoco.ts';

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index++) {
    difference |= a.charCodeAt(index) ^ b.charCodeAt(index);
  }
  return difference === 0;
}

async function validSignature(
  secret: string,
  id: string,
  timestamp: string,
  rawBody: string,
  signatureHeader: string,
): Promise<boolean> {
  const timestampSeconds = Number(timestamp);
  if (!Number.isInteger(timestampSeconds) ||
    Math.abs(Date.now() / 1000 - timestampSeconds) > 180) {
    return false;
  }

  if (!secret.startsWith('whsec_')) return false;
  let keyBytes: Uint8Array;
  try {
    keyBytes = Uint8Array.from(atob(secret.slice('whsec_'.length)), (char) =>
      char.charCodeAt(0)
    );
  } catch {
    return false;
  }

  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const content = `${id}.${timestamp}.${rawBody}`;
  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(content),
  );
  const expected = btoa(String.fromCharCode(...new Uint8Array(signature)));
  const candidates = signatureHeader
    .split(' ')
    .map((part) => part.split(','))
    .filter(([version, value]) => version === 'v1' && value)
    .map(([, value]) => value);
  return candidates.some((candidate) => safeEqual(candidate, expected));
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'METHOD_NOT_ALLOWED' }, 405);
  }

  try {
    const secret = Deno.env.get('YOCO_WEBHOOK_SECRET');
    if (!secret) return notConfigured();

    const id = req.headers.get('webhook-id') ?? '';
    const timestamp = req.headers.get('webhook-timestamp') ?? '';
    const signature = req.headers.get('webhook-signature') ?? '';
    const rawBody = await req.text();

    if (!id || !timestamp || !signature ||
      !await validSignature(secret, id, timestamp, rawBody, signature)) {
      console.warn('yoco-webhook: rejected unsigned, stale or invalid request');
      return json({ error: 'INVALID_SIGNATURE' }, 401);
    }

    const event = JSON.parse(rawBody);
    if (event?.type !== 'payment.succeeded' &&
      event?.type !== 'payment.failed') {
      return json({ ignored: event?.type ?? 'unknown' });
    }

    const payload = event.payload;
    if (payload?.type !== 'payment' || typeof payload.id !== 'string') {
      return json({ error: 'INVALID_EVENT' }, 400);
    }

    const checkoutId = payload.metadata?.checkoutId;
    if (typeof checkoutId !== 'string' || !checkoutId) {
      console.error('yoco-webhook: event missing checkoutId metadata');
      return json({ error: 'CHECKOUT_ID_REQUIRED' }, 400);
    }

    const admin = adminClient();
    const result = await applyYocoPaymentResult(
      admin,
      checkoutId,
      payload,
      event.type === 'payment.succeeded',
    );
    if (result.reason === 'unknown_reference') {
      console.warn(
        'yoco-webhook: payment record not available yet; asking Yoco to retry',
      );
      return json({ error: 'PAYMENT_NOT_READY' }, 503);
    }
    return json({ ok: true, reason: result.reason });
  } catch (error) {
    console.error('yoco-webhook failed:', error);
    return json({ error: 'INTERNAL_ERROR' }, 500);
  }
});
