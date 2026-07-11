// Handles PUT /upload/<any/path/here> — same origin as index.html,
// deployed automatically by Cloudflare Pages from the /functions folder.
// Requires: an R2 bucket binding named TREE_MODELS, and environment
// variables SUPABASE_URL + SUPABASE_ANON_KEY, both set in the Pages
// project's dashboard (Settings → Functions / Environment variables).

export async function onRequestPut(context) {
  const { request, env, params } = context;

  const rawPath = Array.isArray(params.path) ? params.path.join('/') : params.path;
  const path = decodeURIComponent(rawPath || '');
  if (!path || path.includes('..')) {
    return new Response('Invalid path', { status: 400 });
  }

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

  const contentType = request.headers.get('Content-Type') || 'application/octet-stream';

  await env.TREE_MODELS.put(path, request.body, {
    httpMetadata: { contentType },
  });

  return new Response(JSON.stringify({ success: true, path }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'PUT, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    },
  });
}