export { SessionDO } from './session/session_do.ts';

export default {
  async fetch(req: Request, env: any) {
    if (new URL(req.url).pathname === '/health') return new Response('OK');
    const { sessionId, type, payload } = await req.json();
    const id = env.SESSION_DO.idFromName(sessionId);
    return env.SESSION_DO.get(id).fetch('https://do', {
      method: 'POST',
      body: JSON.stringify({ type, payload }),
    });
  }
};
