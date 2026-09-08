import { generateOTP, generateSessionToken, generateUserId, OTPConfig } from './otp';
import { EmailService } from './email';

export interface AuthManagerDeps {
  db: any; // D1 Database
  kv: any; // Cloudflare KV
  email: EmailService;
  otpConfig?: Partial<OTPConfig>;
}

export class AuthManager {
  private db: any;
  private kv: any;
  private email: EmailService;
  private otpConfig: OTPConfig;

  constructor(deps: AuthManagerDeps) {
    this.db = deps.db;
    this.kv = deps.kv;
    this.email = deps.email;
    this.otpConfig = {
      length: 6,
      expiryMinutes: 10,
      maxAttempts: 3,
      ...deps.otpConfig,
    };
  }

  // Step 1: Request OTP
  async requestOTP(email: string): Promise<{ success: boolean; message: string }> {
    email = email.toLowerCase().trim();
    if (!this.isValidEmail(email)) {
      return { success: false, message: 'Invalid email address' };
    }

    try {
      // Check rate limiting in KV
      const rateLimitKey = `otp:ratelimit:${email}`;
      const recentAttempts = await this.kv.get(rateLimitKey);
      if (recentAttempts) {
        const attempts = JSON.parse(recentAttempts);
        if (attempts.count >= 5) {
          return { success: false, message: 'Too many attempts, please try later' };
        }
        attempts.count++;
        await this.kv.put(rateLimitKey, JSON.stringify(attempts), { expirationTtl: 3600 });
      } else {
        await this.kv.put(
          rateLimitKey,
          JSON.stringify({ count: 1, timestamp: Date.now() }),
          { expirationTtl: 3600 }
        );
      }

      // Generate OTP
      const code = generateOTP(this.otpConfig);
      const expiresAt = new Date(Date.now() + this.otpConfig.expiryMinutes * 60 * 1000);
      const id = `otp_${Date.now()}_${Math.random().toString(36).slice(2)}`;

      // Store in D1
      await this.db
        .prepare(
          `INSERT INTO otp_codes (id, email, code, created_at, expires_at, attempts, max_attempts)
           VALUES (?, ?, ?, datetime('now'), ?, 0, ?)`
        )
        .bind(id, email, code, expiresAt.toISOString(), this.otpConfig.maxAttempts)
        .run();

      // Cache in KV for faster verification
      const kvKey = `otp:${email}:${code}`;
      await this.kv.put(kvKey, JSON.stringify({ email, code, id }), {
        expirationTtl: this.otpConfig.expiryMinutes * 60,
      });

      // Send email
      await this.email.sendOTP(email, code);

      return { success: true, message: 'OTP sent to email' };
    } catch (error) {
      console.error('OTP request failed:', error);
      return { success: false, message: 'Failed to send OTP' };
    }
  }

  // Step 2: Verify OTP
  async verifyOTP(email: string, code: string): Promise<{ success: boolean; token?: string; message: string }> {
    email = email.toLowerCase().trim();
    code = code.trim();

    try {
      // Try KV first (faster)
      const kvKey = `otp:${email}:${code}`;
      const cached = await this.kv.get(kvKey);

      if (cached) {
        // OTP exists in KV, still valid
        const otpData = JSON.parse(cached);

        // Get or create user
        let user = await this.db
          .prepare('SELECT * FROM users WHERE email = ?')
          .bind(email)
          .first();

        if (!user) {
          const userId = generateUserId();
          await this.db
            .prepare('INSERT INTO users (id, email) VALUES (?, ?)')
            .bind(userId, email)
            .run();
          user = { id: userId, email };
        }

        // Create session
        const sessionToken = generateSessionToken();
        const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days

        await this.db
          .prepare(
            `INSERT INTO sessions (id, user_id, token, created_at, expires_at)
             VALUES (?, ?, ?, datetime('now'), ?)`
          )
          .bind(`sess_${Date.now()}`, user.id, sessionToken, expiresAt.toISOString())
          .run();

        // Mark OTP as used in D1
        await this.db
          .prepare('UPDATE otp_codes SET used = 1 WHERE id = ?')
          .bind(otpData.id)
          .run();

        // Clean up KV
        await this.kv.delete(kvKey);

        return { success: true, token: sessionToken, message: 'OTP verified' };
      }

      // Fall back to D1 if not in cache
      const result = await this.db
        .prepare(
          `SELECT * FROM otp_codes
           WHERE email = ? AND code = ? AND used = 0 AND expires_at > datetime('now')`
        )
        .bind(email, code)
        .first();

      if (!result) {
        return { success: false, message: 'Invalid or expired OTP' };
      }

      if (result.attempts >= result.max_attempts) {
        return { success: false, message: 'OTP attempts exceeded' };
      }

      // OTP valid, proceed with user/session creation
      let user = await this.db
        .prepare('SELECT * FROM users WHERE email = ?')
        .bind(email)
        .first();

      if (!user) {
        const userId = generateUserId();
        await this.db
          .prepare('INSERT INTO users (id, email) VALUES (?, ?)')
          .bind(userId, email)
          .run();
        user = { id: userId, email };
      }

      // Create session
      const sessionToken = generateSessionToken();
      const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

      await this.db
        .prepare(
          `INSERT INTO sessions (id, user_id, token, created_at, expires_at)
           VALUES (?, ?, ?, datetime('now'), ?)`
        )
        .bind(`sess_${Date.now()}`, user.id, sessionToken, expiresAt.toISOString())
        .run();

      // Mark OTP as used
      await this.db
        .prepare('UPDATE otp_codes SET used = 1 WHERE id = ?')
        .bind(result.id)
        .run();

      return { success: true, token: sessionToken, message: 'OTP verified' };
    } catch (error) {
      console.error('OTP verification failed:', error);
      return { success: false, message: 'Verification failed' };
    }
  }

  // Verify session token
  async verifySession(token: string): Promise<{ success: boolean; userId?: string; user?: any }> {
    try {
      const session = await this.db
        .prepare(
          `SELECT s.*, u.* FROM sessions s
           JOIN users u ON s.user_id = u.id
           WHERE s.token = ? AND s.expires_at > datetime('now')`
        )
        .bind(token)
        .first();

      if (!session) {
        return { success: false };
      }

      return {
        success: true,
        userId: session.user_id,
        user: {
          id: session.id,
          email: session.email,
          name: session.name,
          personaId: session.persona_id,
        },
      };
    } catch (error) {
      console.error('Session verification failed:', error);
      return { success: false };
    }
  }

  private isValidEmail(email: string): boolean {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  }
}
