import { AuthManager } from '../auth/manager';
import { BrevoEmailService } from '../auth/email';

interface AuthEnv {
  DB: any;
  OTP_KV: any;
  BREVO_API_KEY: string;
}

export async function handleAuthRequest(req: Request, env: AuthEnv): Promise<Response> {
  const url = new URL(req.url);
  const pathname = url.pathname;

  // CORS headers
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Content-Type': 'application/json',
  };

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const emailService = new BrevoEmailService(env.BREVO_API_KEY);
  const authManager = new AuthManager({
    db: env.DB,
    kv: env.OTP_KV,
    email: emailService,
  });

  try {
    // POST /api/auth/request-otp
    if (pathname === '/api/auth/request-otp' && req.method === 'POST') {
      const { email } = await req.json();
      if (!email) {
        return new Response(
          JSON.stringify({ success: false, message: 'Email is required' }),
          { status: 400, headers: corsHeaders }
        );
      }

      const result = await authManager.requestOTP(email);
      return new Response(JSON.stringify(result), {
        status: result.success ? 200 : 400,
        headers: corsHeaders,
      });
    }

    // POST /api/auth/verify-otp
    if (pathname === '/api/auth/verify-otp' && req.method === 'POST') {
      const { email, code } = await req.json();
      if (!email || !code) {
        return new Response(
          JSON.stringify({ success: false, message: 'Email and code are required' }),
          { status: 400, headers: corsHeaders }
        );
      }

      const result = await authManager.verifyOTP(email, code);
      return new Response(JSON.stringify(result), {
        status: result.success ? 200 : 400,
        headers: corsHeaders,
      });
    }

    // GET /api/auth/verify-session
    if (pathname === '/api/auth/verify-session' && req.method === 'GET') {
      const token = req.headers.get('Authorization')?.replace('Bearer ', '');
      if (!token) {
        return new Response(
          JSON.stringify({ success: false, message: 'Missing token' }),
          { status: 401, headers: corsHeaders }
        );
      }

      const result = await authManager.verifySession(token);
      return new Response(JSON.stringify(result), {
        status: result.success ? 200 : 401,
        headers: corsHeaders,
      });
    }

    return new Response(JSON.stringify({ error: 'Not found' }), {
      status: 404,
      headers: corsHeaders,
    });
  } catch (error) {
    console.error('Auth error:', error);
    return new Response(
      JSON.stringify({ success: false, message: 'Internal server error' }),
      { status: 500, headers: corsHeaders }
    );
  }
}
