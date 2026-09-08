import crypto from 'crypto';

export interface OTPConfig {
  length: number;
  expiryMinutes: number;
  maxAttempts: number;
}

const DEFAULT_CONFIG: OTPConfig = {
  length: 6,
  expiryMinutes: 10,
  maxAttempts: 3,
};

export function generateOTP(config: Partial<OTPConfig> = {}): string {
  const c = { ...DEFAULT_CONFIG, ...config };
  const min = Math.pow(10, c.length - 1);
  const max = Math.pow(10, c.length) - 1;
  return Math.floor(Math.random() * (max - min + 1) + min).toString();
}

export function generateSessionToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

export function generateUserId(): string {
  return `user_${Date.now()}_${Math.random().toString(36).slice(2)}`;
}
