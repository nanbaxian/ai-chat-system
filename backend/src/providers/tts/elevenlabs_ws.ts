import { StreamingTTS } from '../../router/tts_types';

type ElevenAudioMsg = { audio?: string; isFinal?: boolean; [k: string]: any };

export class ElevenLabsStreamingTTS implements StreamingTTS {
  private ws?: WebSocket;
  private audioCb?: (buf: ArrayBuffer) => void;
  private opened = false;

  constructor(
    private apiKey: string,
    private voiceId: string = 'EXAVITQu4vr4xnSDxMaL',
    private modelId: string = 'eleven_turbo_v2_5',
    private outputFormat: string = 'pcm_24000'
  ) {}

  async start(): Promise<void> {
    const url = `wss://api.elevenlabs.io/v1/text-to-speech/${this.voiceId}/stream-input?model_id=${encodeURIComponent(this.modelId)}&output_format=${encodeURIComponent(this.outputFormat)}&auto_mode=true`;
    this.ws = new WebSocket(url, { headers: { 'xi-api-key': this.apiKey } } as any);

    await new Promise<void>((resolve, reject) => {
      const onOpen = () => { this.opened = true; resolve(); };
      const onErr = (e: any) => reject(e);
      (this.ws as any).addEventListener?.('open', onOpen);
      (this.ws as any).addEventListener?.('error', onErr);
      // node ws uses 'on'
      (this.ws as any).on?.('open', onOpen);
      (this.ws as any).on?.('error', onErr);
    });

    // Initialize connection per ElevenLabs docs: send a space with settings + key
    this.ws.send(JSON.stringify({
      text: ' ',
      voice_settings: { stability: 0.5, similarity_boost: 0.8, speed: 1.0 },
      xi_api_key: this.apiKey
    }));
    
    // Receive messages with base64 audio chunks
    (this.ws as any).on?.('message', (raw: any) => {
      try {
        const msg: ElevenAudioMsg = JSON.parse(raw.toString());
        if (msg.audio) {
          const bytes = Uint8Array.from(Buffer.from(msg.audio, 'base64'));
          this.audioCb?.(bytes.buffer);
        }
      } catch { /* ignore */ }
    });
  }

  sendText(text: string): void {
    if (!this.ws || !this.opened) throw new Error('ElevenLabs WS not ready');
    // try_trigger_generation helps push partial text into audio
    this.ws.send(JSON.stringify({ text, try_trigger_generation: true }));
  }

  onAudio(cb: (buf: ArrayBuffer) => void): void {
    this.audioCb = cb;
  }

  abort(): void {
    try {
      if (this.ws && this.opened) {
        // Close message: send empty text then close socket (per docs)
        this.ws.send(JSON.stringify({ text: '' }));
      }
    } catch {}
    try { this.ws?.close(); } catch {}
    this.ws = undefined;
    this.opened = false;
  }
}
