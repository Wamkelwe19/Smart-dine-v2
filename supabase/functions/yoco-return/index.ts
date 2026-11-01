// Yoco's hosted checkout redirects here; payment success is never inferred
// from this redirect. The signed webhook remains authoritative.

const SCHEME = 'za.ac.ump.smartdine';
const PACKAGE = 'za.ac.ump.smartdine';

Deno.serve((req) => {
  const url = new URL(req.url);
  const raw = url.searchParams.get('reference') ?? '';
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
