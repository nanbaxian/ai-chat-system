import { SessionDO } from './session/session_do';

export default {
  async fetch(req: Request, env: any) {
    const url = new URL(req.url);

    // --- Auth hook (JWT / API key placeholder) ---
    const auth = req.headers.get('Authorization');
    if (!auth) {
      return new Response('Unauthorized', { status: 401 });
    }

    if (url.pathname === '/signal' && req.method === 'POST') {
      const { sessionId, type, payload } = await req.json();
      const id = env.SESSION_DO.idFromName(sessionId);
      const stub = env.SESSION_DO.get(id);
      return stub.fetch('https://do/signal', {
        method: 'POST',
        headers: { Authorization: auth },
        body: JSON.stringify({ type, payload }),
      });
    }

    return new Response('Not Found', { status: 404 });
  }
};
