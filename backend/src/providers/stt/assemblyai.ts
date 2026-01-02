import WebSocket from 'ws';

export class AssemblyAIStreamingSTT {
  private ws?: WebSocket;
  private onPartial?: (t: string) => void;
  private onFinal?: (t: string) => void;

  constructor(private apiKey: string) {}

  async start() {
    if (!this.apiKey) {
      console.warn('[STT] AssemblyAI API key missing');
    }
    this.ws = new WebSocket('wss://api.assemblyai.com/v2/realtime/ws?sample_rate=16000', {
      headers: { Authorization: this.apiKey }
    });

    this.ws.on('open', () => {
      console.log('[STT] AssemblyAI websocket opened');
    });
    this.ws.on('close', (code, reason) => {
      console.log('[STT] AssemblyAI websocket closed', code, reason.toString().slice(0, 64));
    });
    this.ws.on('error', (error) => {
      console.error('[STT] AssemblyAI websocket error', error);
    });

    this.ws.on('message', (msg) => {
      console.log('[STT] websocket message', msg.toString().substring(0, 160));
      const data = JSON.parse(msg.toString());
      if (data.text && !data.is_final) this.onPartial?.(data.text);
      if (data.text && data.is_final) this.onFinal?.(data.text);
    });
  }

  sendAudio(chunk: ArrayBuffer) {
    if (!this.ws) return;
    const buf = Buffer.from(chunk);
    console.log('[STT] sending chunk', buf.length);
    this.ws.send(JSON.stringify({ audio_data: buf.toString('base64') }));
  }

  onPartialText(cb: (t: string) => void) {
    this.onPartial = cb;
  }

  onFinalText(cb: (t: string) => void) {
    this.onFinal = cb;
  }

  close() {
    this.ws?.close();
  }
}
