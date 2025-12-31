import { StreamingTTS } from '../../router/tts_types';

export class DeepgramStreamingTTS implements StreamingTTS {
  private ws?: WebSocket;
  private audioCb?: (buf: ArrayBuffer) => void;
  private opened = false;

  constructor(
    private apiKey: string,
    private model: string = 'aura-asteria-en',
    private encoding: string = 'linear16',
    private sampleRate: number = 24000
  ) {}

  async start(): Promise<void> {
    const url = `wss://api.deepgram.com/v1/speak?model=${encodeURIComponent(this.model)}&encoding=${encodeURIComponent(this.encoding)}&sample_rate=${this.sampleRate}`;
    this.ws = new WebSocket(url, { headers: { 'Authorization': `Token ${this.apiKey}` } } as any);

    await new Promise<void>((resolve, reject) => {
      const onOpen = () => { this.opened = true; resolve(); };
      const onErr = (e: any) => reject(e);
      (this.ws as any).addEventListener?.('open', onOpen);
      (this.ws as any).addEventListener?.('error', onErr);
      (this.ws as any).on?.('open', onOpen);
      (this.ws as any).on?.('error', onErr);
    });

    // Binary audio frames arrive as WS binary messages
    (this.ws as any).on?.('message', (raw: any) => {
      // Deepgram sends audio as binary and control messages as JSON
      if (Buffer.isBuffer(raw)) {
        const buf = raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength);
        this.audioCb?.(buf);
        return;
      }
      try {
        const msg = JSON.parse(raw.toString());
        // ignore metadata / flushed / warnings
        void msg;
      } catch { /* ignore */ }
    });
  }

  sendText(text: string): void {
    if (!this.ws || !this.opened) throw new Error('Deepgram WS not ready');
    this.ws.send(JSON.stringify({ type: 'Speak', text }));
  }

  onAudio(cb: (buf: ArrayBuffer) => void): void {
    this.audioCb = cb;
  }

  abort(): void {
    try {
      if (this.ws && this.opened) {
        // Clear then Close to stop quickly (docs support Clear)
        this.ws.send(JSON.stringify({ type: 'Clear' }));
        this.ws.send(JSON.stringify({ type: 'Close' }));
      }
    } catch {}
    try { this.ws?.close(); } catch {}
    this.ws = undefined;
    this.opened = false;
  }
}
