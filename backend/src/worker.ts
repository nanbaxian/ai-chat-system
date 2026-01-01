export { SessionDO } from './session/session_do.ts';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

function withCors(res: Response) {
  const headers = new Headers(res.headers);
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    headers.set(key, value);
  }
  return new Response(res.body, { status: res.status, headers });
}

export default {
  async fetch(req: Request, env: any) {
    const url = new URL(req.url);
    const method = (req.method ?? 'GET').toUpperCase();

    if (method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }

    if (!url.pathname.startsWith('/signal')) {
      return withCors(new Response('Not Found', { status: 404 }));
    }

    const auth = req.headers.get('Authorization');
    if (!auth) return withCors(new Response('Unauthorized', { status: 401 }));

    let body: any = {};
    if (req.body && method === 'POST') {
      try {
        body = await req.json();
      } catch (e) {
        console.warn('Failed to parse signal body', e);
        return withCors(new Response('Invalid body', { status: 400 }));
      }
    }

    const { sessionId, type, payload } = body ?? {};
    if (!sessionId || !type) {
      return withCors(new Response('Missing sessionId/type', { status: 400 }));
    }

    const id = env.SESSION_DO.idFromName(sessionId);
    const stub = env.SESSION_DO.get(id);
    const resp = await stub.fetch('https://do/signal', {
      method: 'POST',
      headers: { Authorization: auth },
      body: JSON.stringify({ type, payload }),
    });
    return withCors(resp);
  },
};
