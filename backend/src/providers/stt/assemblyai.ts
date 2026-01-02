import WebSocket from 'ws';
import querystring from 'querystring';

const DEFAULT_SAMPLE_RATE = 16000;
const DEFAULT_FORMAT_TURNS = true;
const API_ENDPOINT_BASE = 'wss://streaming.assemblyai.com/v3/ws';

function buildEndpoint(sampleRate: number) {
  const params = {
    sample_rate: sampleRate,
    format_turns: DEFAULT_FORMAT_TURNS ? 'true' : 'false'
  };
  return `${API_ENDPOINT_BASE}?${querystring.stringify(params)}`;
}

export class AssemblyAIStreamingSTT {
  private ws?: WebSocket;
  private onPartial?: (t: string) => void;
  private onFinal?: (t: string) => void;

  constructor(private apiKey: string, private sampleRate = DEFAULT_SAMPLE_RATE) {}

  async start() {
    if (!this.apiKey) {
      console.warn('[STT] AssemblyAI API key missing');
    }
    const endpoint = buildEndpoint(this.sampleRate);
    this.ws = new WebSocket(endpoint, {
      headers: { Authorization: this.apiKey }
    });

    this.ws.on('open', () => {
      console.log('[STT] AssemblyAI websocket opened', endpoint);
    });
    this.ws.on('close', (code, reason) => {
      console.log('[STT] AssemblyAI websocket closed', code, reason.toString().slice(0, 64));
    });
    this.ws.on('error', (error) => {
      console.error('[STT] AssemblyAI websocket error', error);
    });

    this.ws.on('message', (msg) => {
      const text = msg.toString();
      console.log('[STT] websocket message', text.length > 160 ? `${text.slice(0, 160)}…` : text);
      const data = JSON.parse(text);
      if (data.text && !data.is_final) this.onPartial?.(data.text);
      if (data.text && data.is_final) this.onFinal?.(data.text);
    });
  }

  sendAudio(chunk: ArrayBuffer) {
    if (!this.ws) return;
    const buffer = Buffer.from(chunk);
    console.log('[STT] sending chunk (binary) length', buffer.length);
    this.ws.send(buffer);
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
