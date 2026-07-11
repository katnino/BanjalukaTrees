// ============================================================
// Cloudflare Pages Function — upload 3D models to Backblaze B2
// ============================================================
// Environment variables (set in Cloudflare Pages dashboard):
//   SUPABASE_URL           — Supabase project URL (for auth)
//   SUPABASE_ANON_KEY      — Supabase anon key
//   B2_ENDPOINT            — e.g. "s3.us-west-001.backblazeb2.com"
//   B2_REGION              — e.g. "us-west-001"
//   B2_ACCESS_KEY_ID       — B2 Application Key ID
//   B2_SECRET_ACCESS_KEY   — B2 Application Key
//   B2_BUCKET              — bucket name
// ============================================================
// Usage: curl -X PUT https://your-site.pages.dev/upload/path/to/model.glb \
//   -H "Authorization: Bearer <supabase-session-token>" \
//   -H "Content-Type: model/gltf-binary" \
//   --data-binary @model.glb
// ============================================================

const TEXT_ENCODER = new TextEncoder();

export async function onRequestPut(context) {
  const { request, env, params } = context;

  // ---- 1. Validate path ----
  const rawPath = Array.isArray(params.path) ? params.path.join('/') : params.path;
  const path = decodeURIComponent(rawPath || '');
  if (!path || path.includes('..')) {
    return new Response('Invalid path', { status: 400 });
  }

  // ---- 2. Authenticate via Supabase ----
  const authHeader = request.headers.get('Authorization') || '';
  const token = authHeader.replace('Bearer ', '');
  if (!token) {
    return new Response('Missing auth token', { status: 401 });
  }

  const userCheck = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: {
      apikey: env.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${token}`,
    },
  });

  if (!userCheck.ok) {
    return new Response('Unauthorized', { status: 401 });
  }

  // ---- 3. Upload to Backblaze B2 via S3-compatible API ----
  const contentType = request.headers.get('Content-Type') || 'application/octet-stream';
  const body = await request.arrayBuffer();
  const bodyBytes = new Uint8Array(body);

  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]/g, '').replace(/\.\d{3}Z$/, 'Z');
  const dateStamp = amzDate.slice(0, 8);

  const url = `https://${env.B2_ENDPOINT}/${env.B2_BUCKET}/${path}`;
  const parsedUrl = new URL(url);

  // Hash the payload
  const payloadHash = await sha256(bodyBytes);

  // ---- Build canonical request (AWS Signature V4) ----
  const canonicalHeaders = [
    `host:${parsedUrl.host}`,
    `x-amz-content-sha256:${payloadHash}`,
    `x-amz-date:${amzDate}`,
  ];
  const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';

  const canonicalRequest = [
    'PUT',
    parsedUrl.pathname,
    '',                      // no query string
    ...canonicalHeaders,
    '',                      // blank line separator
    signedHeaders,
    payloadHash,
  ].join('\n');

  // ---- Derive signing key ----
  const kSecret = TEXT_ENCODER.encode('AWS4' + env.B2_SECRET_ACCESS_KEY);
  const kDate = await hmacSha256(kSecret, TEXT_ENCODER.encode(dateStamp));
  const kRegion = await hmacSha256(kDate, TEXT_ENCODER.encode(env.B2_REGION));
  const kService = await hmacSha256(kRegion, TEXT_ENCODER.encode('s3'));
  const kSigning = await hmacSha256(kService, TEXT_ENCODER.encode('aws4_request'));

  // ---- Create string to sign ----
  const canonicalRequestHash = await sha256(TEXT_ENCODER.encode(canonicalRequest));
  const scope = `${dateStamp}/${env.B2_REGION}/s3/aws4_request`;
  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    canonicalRequestHash,
  ].join('\n');

  // ---- Sign ----
  const signature = hex(await hmacSha256(kSigning, TEXT_ENCODER.encode(stringToSign)));
  const credential = `${env.B2_ACCESS_KEY_ID}/${scope}`;
  const authorizationHeader =
    `AWS4-HMAC-SHA256 Credential=${credential},SignedHeaders=${signedHeaders},Signature=${signature}`;

  // ---- Upload to B2 ----
  const response = await fetch(url, {
    method: 'PUT',
    headers: {
      'Authorization': authorizationHeader,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      'Content-Type': contentType,
    },
    body: body,
  });

  if (!response.ok) {
    const text = await response.text();
    console.error('B2 upload failed:', response.status, text);
    return new Response(`B2 upload failed: ${response.status} ${text}`, {
      status: 502,
    });
  }

  // ---- 4. Return success with the public download URL ----
  const publicUrl = `https://${env.B2_ENDPOINT}/${env.B2_BUCKET}/${path}`;
  return new Response(JSON.stringify({ success: true, path, url: publicUrl }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

// ---- CORS preflight ----
export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'PUT, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    },
  });
}

// ---- Crypto helpers (Web Crypto API) ----

async function sha256(data) {
  const input = data instanceof Uint8Array ? data : TEXT_ENCODER.encode(data);
  const hash = await crypto.subtle.digest('SHA-256', input);
  return hex(new Uint8Array(hash));
}

async function hmacSha256(key, data) {
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    key instanceof Uint8Array ? key : TEXT_ENCODER.encode(key),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    cryptoKey,
    data instanceof Uint8Array ? data : TEXT_ENCODER.encode(data),
  );
  return new Uint8Array(sig);
}

function hex(bytes) {
  return [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
}
