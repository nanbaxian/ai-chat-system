import { AuthManager } from '../auth/manager';
import { BrevoEmailService } from '../auth/email';

export interface AuthContext {
  userId?: string;
  user?: any;
  token?: string;
}

export async function verifyAuth(
  req: Request,
  db: any,
  kv: any
): Promise<{ context: AuthContext; error?: string }> {
  const authHeader = req.headers.get('Authorization');

  if (!authHeader) {
    return { context: {} };
  }

  const token = authHeader.replace('Bearer ', '').trim();
  if (!token) {
    return { context: {}, error: 'Invalid authorization header' };
  }

  try {
    const authManager = new AuthManager({
      db,
      kv,
      email: new BrevoEmailService(''),
    });

    const result = await authManager.verifySession(token);
    if (!result.success) {
      return { context: {}, error: 'Invalid or expired token' };
    }

    return {
      context: {
        userId: result.userId,
        user: result.user,
        token,
      },
    };
  } catch (error) {
    return { context: {}, error: 'Auth verification failed' };
  }
}

export function corsResponse(body: any, status = 200, origin = '*'): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Allow-Credentials': 'true',
    },
  });
}

export function errorResponse(message: string, status = 400, origin = '*'): Response {
  return corsResponse({ error: message }, status, origin);
}
