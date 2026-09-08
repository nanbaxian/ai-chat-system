// 扩展的认证功能

export interface User {
  id: string;
  email: string;
  name?: string;
  personaId?: string;
  createdAt: string;
  updatedAt: string;
}

export interface Session {
  id: string;
  userId: string;
  token: string;
  expiresAt: string;
  ipAddress?: string;
  userAgent?: string;
}

export class UserManager {
  constructor(private db: any) {}

  async updateProfile(userId: string, updates: { name?: string; personaId?: string }): Promise<{ success: boolean; user?: User; error?: string }> {
    try {
      const sql = `
        UPDATE users
        SET ${Object.keys(updates).map((k, i) => `${k} = ?`).join(', ')},
            updated_at = datetime('now')
        WHERE id = ?
        RETURNING *
      `;

      const values = [...Object.values(updates), userId];
      const user = await this.db.prepare(sql).bind(...values).first();

      return { success: !!user, user };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  async getProfile(userId: string): Promise<{ success: boolean; user?: User; error?: string }> {
    try {
      const user = await this.db
        .prepare('SELECT * FROM users WHERE id = ?')
        .bind(userId)
        .first();

      return { success: !!user, user };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  async deleteAccount(userId: string): Promise<{ success: boolean; error?: string }> {
    try {
      // 删除所有相关数据（级联删除）
      await this.db.prepare('DELETE FROM users WHERE id = ?').bind(userId).run();
      return { success: true };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }
}

export class SessionManager {
  constructor(private db: any, private kv: any) {}

  async revokeToken(token: string): Promise<{ success: boolean; error?: string }> {
    try {
      const revokeKey = `revoked:${token}`;
      await this.kv.put(revokeKey, 'true', { expirationTtl: 30 * 24 * 60 * 60 }); // 30天后过期
      return { success: true };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  async isTokenRevoked(token: string): Promise<boolean> {
    try {
      const revoked = await this.kv.get(`revoked:${token}`);
      return revoked === 'true';
    } catch {
      return false;
    }
  }

  async getAllSessions(userId: string): Promise<Session[]> {
    try {
      const sessions = await this.db
        .prepare('SELECT * FROM sessions WHERE user_id = ? AND expires_at > datetime("now") ORDER BY created_at DESC')
        .bind(userId)
        .all();
      return sessions.results || [];
    } catch {
      return [];
    }
  }

  async revokeAllSessions(userId: string): Promise<{ success: boolean; error?: string }> {
    try {
      const sessions = await this.getAllSessions(userId);
      for (const session of sessions) {
        await this.revokeToken(session.token);
      }
      return { success: true };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }
}

export class AuditLogger {
  constructor(private db: any) {}

  async logAction(
    userId: string,
    action: string,
    details: Record<string, any> = {},
    ipAddress?: string
  ): Promise<void> {
    try {
      await this.db
        .prepare(
          `INSERT INTO audit_logs (id, user_id, action, details, ip_address, created_at)
           VALUES (?, ?, ?, ?, ?, datetime('now'))`
        )
        .bind(
          `log_${Date.now()}_${Math.random().toString(36).slice(2)}`,
          userId,
          action,
          JSON.stringify(details),
          ipAddress
        )
        .run();
    } catch (error) {
      console.error('Audit log failed:', error);
    }
  }

  async getActionHistory(userId: string, limit = 50): Promise<any[]> {
    try {
      const logs = await this.db
        .prepare(
          'SELECT * FROM audit_logs WHERE user_id = ? ORDER BY created_at DESC LIMIT ?'
        )
        .bind(userId, limit)
        .all();
      return logs.results || [];
    } catch {
      return [];
    }
  }
}
