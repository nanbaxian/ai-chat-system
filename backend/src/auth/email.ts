export interface EmailService {
  sendOTP(email: string, code: string): Promise<void>;
}

export class BrevoEmailService implements EmailService {
  private apiKey: string;
  private apiUrl = 'https://api.brevo.com/v3/smtp/email';

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  async sendOTP(email: string, code: string): Promise<void> {
    const html = `
      <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto;">
        <h2>Your Verification Code</h2>
        <p style="font-size: 16px; color: #666;">Enter this code to verify your email address:</p>
        <div style="background: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0; text-align: center;">
          <div style="font-size: 36px; font-weight: bold; color: #333; letter-spacing: 2px;">${code}</div>
        </div>
        <p style="font-size: 14px; color: #999;">This code expires in 10 minutes.</p>
        <p style="font-size: 12px; color: #ccc; margin-top: 40px; border-top: 1px solid #eee; padding-top: 20px;">
          Do not share this code with anyone.
        </p>
      </div>
    `;

    const response = await fetch(this.apiUrl, {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'api-key': this.apiKey,
      },
      body: JSON.stringify({
        sender: {
          name: 'Voice AI',
          email: 'noreply@myworlds.ca',
        },
        to: [{ email }],
        subject: 'Your Verification Code',
        htmlContent: html,
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Brevo email failed: ${response.status} ${error}`);
    }
  }
}
