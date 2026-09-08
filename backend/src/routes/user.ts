import { UserManager, SessionManager, AuditLogger } from '../auth/extended';

interface UserEnv {
  DB: any;
  OTP_KV: any;
}

export async function handleUserRequest(req: Request, env: UserEnv, userId?: string): Promise<Response> {
  const url = new URL(req.url);
  const pathname = url.pathname;

  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Content-Type': 'application/json',
  };

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (!userId) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: corsHeaders,
    });
  }

  const userManager = new UserManager(env.DB);
  const sessionManager = new SessionManager(env.DB, env.OTP_KV);
  const auditLogger = new AuditLogger(env.DB);

  const clientIp = req.headers.get('CF-Connecting-IP') || 'unknown';

  try {
    // GET /api/user/profile
    if (pathname === '/api/user/profile' && req.method === 'GET') {
      const result = await userManager.getProfile(userId);
      await auditLogger.logAction(userId, 'view_profile', {}, clientIp);
      return new Response(JSON.stringify(result), {
        status: result.success ? 200 : 404,
        headers: corsHeaders,
      });
    }

    // PUT /api/user/profile
    if (pathname === '/api/user/profile' && req.method === 'PUT') {
      const { name, personaId } = await req.json();
      const result = await userManager.updateProfile(userId, { name, personaId });
      await auditLogger.logAction(userId, 'update_profile', { name, personaId }, clientIp);
      return new Response(JSON.stringify(result), {
        status: result.success ? 200 : 400,
        headers: corsHeaders,
      });
    }

    // GET /api/user/sessions
    if (pathname === '/api/user/sessions' && req.method === 'GET') {
      const sessions = await sessionManager.getAllSessions(userId);
      await auditLogger.logAction(userId, 'list_sessions', { count: sessions.length }, clientIp);
      return new Response(
        JSON.stringify({
          success: true,
          sessions: sessions.map(s => ({
            id: s.id,
            createdAt: s.created_at,
            expiresAt: s.expires_at,
            ipAddress: s.ip_address,
          })),
        }),
        { status: 200, headers: corsHeaders }
      );
    }

    // POST /api/user/logout
    if (pathname === '/api/user/logout' && req.method === 'POST') {
      const token = req.headers.get('Authorization')?.replace('Bearer ', '');
      if (token) {
        await sessionManager.revokeToken(token);
        await auditLogger.logAction(userId, 'logout', {}, clientIp);
      }
      return new Response(JSON.stringify({ success: true, message: 'Logged out' }), {
        status: 200,
        headers: corsHeaders,
      });
    }

    // POST /api/user/logout-all
    if (pathname === '/api/user/logout-all' && req.method === 'POST') {
      const result = await sessionManager.revokeAllSessions(userId);
      await auditLogger.logAction(userId, 'logout_all', {}, clientIp);
      return new Response(JSON.stringify(result), {
        status: result.success ? 200 : 400,
        headers: corsHeaders,
      });
    }

    // GET /api/user/audit
    if (pathname === '/api/user/audit' && req.method === 'GET') {
      const limit = parseInt(url.searchParams.get('limit') || '50');
      const history = await auditLogger.getActionHistory(userId, limit);
      return new Response(
        JSON.stringify({ success: true, history }),
        { status: 200, headers: corsHeaders }
      );
    }

    // DELETE /api/user/account
    if (pathname === '/api/user/account' && req.method === 'DELETE') {
      const { password } = await req.json();
      // 在实际应用中应验证密码或二次确认
      await auditLogger.logAction(userId, 'delete_account', {}, clientIp);
      const result = await userManager.deleteAccount(userId);
      return new Response(JSON.stringify(result), {
        status: result.success ? 200 : 400,
        headers: corsHeaders,
      });
    }

    return new Response(JSON.stringify({ error: 'Not found' }), {
      status: 404,
      headers: corsHeaders,
    });
  } catch (error) {
    console.error('User request error:', error);
    return new Response(
      JSON.stringify({ success: false, error: 'Internal server error' }),
      { status: 500, headers: corsHeaders }
    );
  }
}
