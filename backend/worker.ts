import { SessionDO } from './session/session_do';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
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

    // --- Auth hook (JWT / API key placeholder) ---
    const auth = req.headers.get('Authorization');
    if (!auth) {
      return withCors(new Response('Unauthorized', { status: 401 }));
    }

    if (url.pathname === '/signal' && method === 'POST') {
      let body: any = {};
      try {
        body = await req.json();
      } catch (e) {
        console.warn('Failed to parse signal body', e);
      }
      const { sessionId, type, payload } = body ?? {};
      if (!sessionId || !type) {
        return withCors(new Response('Missing sessionId/type', { status: 400 }));
      }
      console.log('[signal] session=%s type=%s payload=%o', sessionId, type, payload);
      const id = env.SESSION_DO.idFromName(sessionId);
      const stub = env.SESSION_DO.get(id);
      const resp = await stub.fetch('https://do/signal', {
        method: 'POST',
        headers: { Authorization: auth },
        body: JSON.stringify({ type, payload }),
      });
      return withCors(resp);
    }

    return withCors(new Response('Not Found', { status: 404 }));
  }
};
