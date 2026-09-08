export { SessionDO } from './session/session_do';
import { handleAuthRequest } from './routes/auth';
import { handleUserRequest } from './routes/user';
import { verifyAuth, corsResponse, errorResponse } from './middleware/auth';

const CORS_HEADERS = {
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Expose-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Credentials': 'true',
};

function withCors(res: Response, origin?: string) {
  const headers = new Headers(res.headers);
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    headers.set(key, value);
  }

  if (origin) {
    headers.set('Access-Control-Allow-Origin', origin);
  }

  return new Response(res.body, { status: res.status, headers });
}

export default {
  async fetch(req: Request, env: any) {
    const url = new URL(req.url);
    const method = (req.method ?? 'GET').toUpperCase();

    if (method === 'OPTIONS') {
      const ori = req.headers.get('Origin') ?? '*';
      return new Response(null, { headers: { ...CORS_HEADERS, 'Access-Control-Allow-Origin': ori } });
    }

    const origin = req.headers.get('Origin') ?? '*';

    // Auth routes
    if (url.pathname.startsWith('/api/auth/')) {
      return handleAuthRequest(req, env);
    }

    // User routes (require authentication)
    if (url.pathname.startsWith('/api/user/')) {
      const { context, error } = await verifyAuth(req, env.DB, env.OTP_KV);
      if (error || !context.userId) {
        return errorResponse('Unauthorized', 401, origin);
      }
      return handleUserRequest(req, env, context.userId);
    }

    if (!url.pathname.startsWith('/signal')) {
      return withCors(new Response('Not Found', { status: 404 }), origin);
    }

    const auth = req.headers.get('Authorization');
    if (!auth) return withCors(new Response('Unauthorized', { status: 401 }), origin);

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
      return withCors(new Response('Missing sessionId/type', { status: 400 }), origin);
    }

    const id = env.SESSION_DO.idFromName(sessionId);
    const stub = env.SESSION_DO.get(id);
    const resp = await stub.fetch('https://do/signal', {
      method: 'POST',
      headers: { Authorization: auth },
      body: JSON.stringify({ type, payload }),
    });
    return withCors(resp, origin);
  },
};
