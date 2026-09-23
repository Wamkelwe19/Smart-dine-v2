// GET /functions/v1/paystack-return?reference=...&trxref=...
//
// Paystack's callback_url must be http(s), so it cannot point straight at the
// app's custom scheme. Paystack sends the browser here after checkout, and this
// bounces it back into UMP Smart Dine with the reference:
//
//   Android: intent://payment-callback?reference=X#Intent;scheme=za.ac.ump.smartdine;
//            package=za.ac.ump.smartdine;end
//   others:  za.ac.ump.smartdine://payment-callback?reference=X
//
// A redirect rather than an HTML page: Supabase serves Edge Function HTML as
// text/plain. If a browser declines the redirect, the app still verifies the
// moment the student switches back to it, so nothing depends on this hop.
//
// Public (deploy with --no-verify-jwt): it reads nothing and writes nothing —
// the payment itself is confirmed server-to-server by paystack-verify and the
// webhook, never by trusting this request.

const SCHEME = 'za.ac.ump.smartdine';
const PACKAGE = 'za.ac.ump.smartdine';

Deno.serve((req) => {
  const url = new URL(req.url);
  const raw = url.searchParams.get('reference') ??
    url.searchParams.get('trxref') ?? '';
  // References are ours: letters, digits and '-' only. Anything else is dropped.
  const reference = /^[A-Za-z0-9.=-]{1,100}$/.test(raw) ? raw : '';
  const query = reference ? `?reference=${encodeURIComponent(reference)}` : '';

  const isAndroid = /android/i.test(req.headers.get('user-agent') ?? '');
  const location = isAndroid
    ? `intent://payment-callback${query}#Intent;scheme=${SCHEME};package=${PACKAGE};end`
    : `${SCHEME}://payment-callback${query}`;

  return new Response(null, {
    status: 302,
    headers: { Location: location, 'Cache-Control': 'no-store' },
  });
});
