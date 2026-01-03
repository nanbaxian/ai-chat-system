import { StreamingTTS } from '../../router/tts_types';

export class DeepgramStreamingTTS implements StreamingTTS {
  private ws?: WebSocket;
  private audioCb?: (buf: ArrayBuffer) => void;
  private opened = false;
  private readonly useHttp: boolean;

  constructor(
    private apiKey: string,
    private model: string = 'aura-asteria-en',
    private encoding: string = 'linear16',
    private sampleRate: number = 24000,
    private voice: string = 'alloy',
    useHttpFallback = false
  ) {
    this.useHttp = useHttpFallback;
  }

  async start(): Promise<void> {
    if (this.useHttp) {
      this.opened = true;
      console.log('[Deepgram] HTTP mode ready');
      return;
    }

    const url = `wss://api.deepgram.com/v1/speak?model=${encodeURIComponent(this.model)}&encoding=${encodeURIComponent(this.encoding)}&sample_rate=${this.sampleRate}`;
    this.ws = new WebSocket(url, { headers: { Authorization: `Token ${this.apiKey}` } } as any);

    await new Promise<void>((resolve, reject) => {
      const onOpen = () => {
        this.opened = true;
        resolve();
      };
      const onErr = (e: any) => reject(e);
      (this.ws as any).addEventListener?.('open', onOpen);
      (this.ws as any).addEventListener?.('error', onErr);
      (this.ws as any).on?.('open', onOpen);
      (this.ws as any).on?.('error', onErr);
    });

    (this.ws as any).on?.('message', (raw: any) => {
      console.log('[deepgram] message received', typeof raw, Buffer.isBuffer(raw) ? raw.byteLength : undefined);
      if (Buffer.isBuffer(raw)) {
        const buf = raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength);
        this.audioCb?.(buf);
        return;
      }
      try {
        const msg = JSON.parse(raw.toString());
        console.log('[deepgram] control message', msg);
      } catch (error) {
        console.error('[deepgram] parse error', error);
      }
    });
  }

  async sendText(text: string): Promise<void> {
    if (this.useHttp) {
      await this.fetchHttpAudio(text);
      return;
    }
    if (!this.ws || !this.opened) throw new Error('Deepgram WS not ready');
    this.ws.send(JSON.stringify({ type: 'Speak', text }));
  }

  onAudio(cb: (buf: ArrayBuffer) => void): void {
    this.audioCb = cb;
  }

  abort(): void {
    try {
      if (this.ws && this.opened) {
        this.ws.send(JSON.stringify({ type: 'Clear' }));
        this.ws.send(JSON.stringify({ type: 'Close' }));
      }
    } catch {}
    try {
      this.ws?.close();
    } catch {}
    this.ws = undefined;
    this.opened = false;
  }

  private async fetchHttpAudio(text: string) {
    console.log('[Deepgram] HTTP sendText', text);
    const res = await fetch('https://api.deepgram.com/v1/text-to-speech', {
      method: 'POST',
      headers: {
        Authorization: `Token ${this.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(this.buildHttpBody(text)),
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`Deepgram HTTP request failed (${res.status}): ${body}`);
    }
    const audio = await res.arrayBuffer();
    console.log('[Deepgram] HTTP chunk received', audio.byteLength, 'bytes');
    this.audioCb?.(audio);
  }

  private buildHttpBody(text: string) {
    return {
      text,
      voice: this.voice,
      model: this.model,
      encoding: this.encoding,
      sample_rate: this.sampleRate,
    };
  }
}
