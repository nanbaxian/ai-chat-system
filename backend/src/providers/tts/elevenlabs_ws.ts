import { appendFile, mkdir } from 'node:fs/promises';
import { Buffer } from 'node:buffer';
import { join } from 'node:path';
import { StreamingTTS } from '../../router/tts_types';

type ElevenAudioMsg = { audio?: string; isFinal?: boolean; [k: string]: any };

export class ElevenLabsStreamingTTS implements StreamingTTS {
  private ws?: WebSocket;
  private audioCb?: (buf: ArrayBuffer) => void;
  private opened = false;
  private readonly logDir = join(process.cwd(), 'logs');
  private readonly logFile = join(this.logDir, 'elevenlabs-tts.log');
  private readonly httpUrl: string;
  private readonly useHttp: boolean;

  constructor(
    private apiKey: string,
    private voiceId: string = 'JBFqnCBsd6RMkjVDRZzb',
    private modelId: string = 'eleven_multilingual_v2',
    private outputFormat: string = 'mp3_44100_128',
    useHttpFallback = false
  ) {
    this.useHttp = useHttpFallback;
    this.httpUrl = `https://api.elevenlabs.io/v1/text-to-speech/${this.voiceId}?model_id=${encodeURIComponent(this.modelId)}`;
  }

  async start(): Promise<void> {
    await this.ensureLogDir();
    if (this.useHttp) {
      this.opened = true;
      console.log('[ElevenLabs] HTTP mode ready');
      return;
    }

    const url = `wss://api.elevenlabs.io/v1/text-to-speech/${this.voiceId}/stream-input?model_id=${encodeURIComponent(this.modelId)}&output_format=${encodeURIComponent(this.outputFormat)}&auto_mode=true`;
    this.ws = new WebSocket(url, { headers: { 'xi-api-key': this.apiKey } } as any);

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

    this.ws.send(
      JSON.stringify({
        text: ' ',
        voice_settings: { stability: 0.5, similarity_boost: 0.8, speed: 1.0 },
        xi_api_key: this.apiKey,
      })
    );

    (this.ws as any).on?.('message', async (raw: any) => {
      try {
        const rawString = typeof raw === 'string' ? raw : raw?.toString?.() ?? '';
        await this.logRaw(rawString);
        const msg: ElevenAudioMsg = JSON.parse(rawString);
        console.log('[ElevenLabs] message', { hasAudio: !!msg.audio, isFinal: msg.isFinal });
        if (msg.audio) {
          await this.logRawChunk(msg.audio);
          const bytes = Uint8Array.from(Buffer.from(msg.audio, 'base64'));
          console.log('[ElevenLabs] delivering audio chunk', bytes.byteLength, 'bytes');
          this.audioCb?.(bytes.buffer);
        }
      } catch (error) {
        console.error('[ElevenLabs] message parse failed', error);
      }
    });
  }

  async sendText(text: string): Promise<void> {
    if (this.useHttp) {
      await this.fetchHttpAudio(text);
      return;
    }
    if (!this.ws || !this.opened) throw new Error('ElevenLabs WS not ready');
    this.ws.send(JSON.stringify({ text, try_trigger_generation: true }));
  }

  onAudio(cb: (buf: ArrayBuffer) => void): void {
    console.log('[ElevenLabs] onAudio', cb, `mode=${this.useHttp ? 'http' : 'ws'}`);
    this.audioCb = cb;
  }

  abort(): void {
    try {
      if (this.ws && this.opened) {
        this.ws.send(JSON.stringify({ text: '' }));
      }
    } catch {}
    try {
      this.ws?.close();
    } catch {}
    this.ws = undefined;
    this.opened = false;
  }

  private async fetchHttpAudio(text: string) {
    console.log('[ElevenLabs] HTTP sendText', text);
    const payload = {
      text,
      voice_settings: { stability: 0.5, similarity_boost: 0.8, speed: 1.0 },
    };
    const res = await fetch(this.httpUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'xi-api-key': this.apiKey,
      },
      body: JSON.stringify(payload),
    });
    if (!res.ok) {
      throw new Error(`ElevenLabs HTTP request failed (${res.status}): ${await res.text()}`);
    }
    const audio = await res.arrayBuffer();
    console.log('[ElevenLabs] HTTP chunk received', audio.byteLength, 'bytes');
    await this.logRawChunk(Buffer.from(audio).toString('base64'));
    this.audioCb?.(audio);
  }

  private async ensureLogDir() {
    try {
      await mkdir(this.logDir, { recursive: true });
    } catch {
      // ignore
    }
  }

  private async logRaw(raw: string) {
    if (!raw) return;
    try {
      await appendFile(this.logFile, `[${new Date().toISOString()}] RAW: ${raw}\n`);
    } catch (error) {
      console.error('[ElevenLabs] logRaw failed', error);
    }
  }

  private async logRawChunk(audio: string) {
    if (!audio) return;
    try {
      await appendFile(this.logFile, `[${new Date().toISOString()}] CHUNK_LEN=${audio.length}\n`);
    } catch (error) {
      console.error('[ElevenLabs] logRawChunk failed', error);
    }
  }
}
