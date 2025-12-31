import WebSocket from 'ws';

export class AssemblyAIStreamingSTT {
  private ws?: WebSocket;
  private onPartial?: (t: string) => void;
  private onFinal?: (t: string) => void;

  constructor(private apiKey: string) {}

  async start() {
    this.ws = new WebSocket(
      'wss://api.assemblyai.com/v2/realtime/ws?sample_rate=16000',
      { headers: { Authorization: this.apiKey } }
    );

    this.ws.on('message', (msg) => {
      const data = JSON.parse(msg.toString());
      if (data.text && !data.is_final) this.onPartial?.(data.text);
      if (data.text && data.is_final) this.onFinal?.(data.text);
    });
  }

  sendAudio(chunk: ArrayBuffer) {
    if (!this.ws) return;
    const buf = Buffer.from(chunk);
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
