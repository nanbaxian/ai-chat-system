import { StreamingTTS } from '../../router/tts_types';

/**
 * PollyStreamingTTS (demo stub)
 *
 * This file exists so the backend builds even if you don't use Polly locally.
 * If AWS credentials are not configured, `start()` throws and the router will
 * automatically fail over to ElevenLabs/Deepgram.
 *
 * You can later replace this with full SigV4 signed Polly streaming.
 */
export class PollyStreamingTTS implements StreamingTTS {
  private cb?: (buf: ArrayBuffer) => void;

  constructor(
    private region?: string,
    private accessKeyId?: string,
    private secretAccessKey?: string,
  ) {}

  async start(): Promise<void> {
    if (!this.accessKeyId || !this.secretAccessKey || !this.region) {
      throw new Error('Polly credentials missing (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_REGION)');
    }
    // TODO: implement true Polly streaming. For demo we rely on router failover if not implemented.
    // If you DO provide creds and still want to force failover, you can keep throwing here.
    throw new Error('PollyStreamingTTS not implemented in this demo stub');
  }

  async sendText(_text: string): Promise<void> {
    // no-op
  }

  onAudio(cb: (buf: ArrayBuffer) => void): void {
    this.cb = cb;
  }

  abort(): void {
    // no-op
  }
}
