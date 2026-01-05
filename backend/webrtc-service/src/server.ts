import path from 'path';
import { fileURLToPath } from 'url';
import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import wrtc from 'wrtc';
import { AssemblyAIStreamingSTT } from '../../src/providers/stt/assemblyai.ts';
import { DeepInfraLLM } from '../../src/providers/llm/deepinfra.ts';
import { PollyStreamingTTS } from '../../src/providers/tts/polly_streaming.ts';
import { ElevenLabsStreamingTTS } from '../../src/providers/tts/elevenlabs_ws.ts';
import { DeepgramStreamingTTS } from '../../src/providers/tts/deepgram_ws.ts';
import { SmartTTSRouter } from '../../src/router/tts_router.ts';
import type { Event as ProtocolEvent } from '../../src/protocol/events.ts';
import { sharedDurableState } from './state.ts';

const AUDIO_SAMPLE_RATE = 24000;

function extractDeltaText(raw: string) {
  if (!raw) return '';
  const lines = raw.split(/\r?\n/);
  let content = '';
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed.startsWith('data:')) continue;
    const payload = trimmed.substring(5).trim();
    if (!payload || payload === '[DONE]') continue;
    try {
      const parsed = JSON.parse(payload);
      const deltaValue = parsed?.choices?.[0]?.delta?.content;
      if (typeof deltaValue === 'string' && deltaValue.length > 0) {
        content += deltaValue;
      }
    } catch {
      // ignore parsing errors
    }
  }
  return content;
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.resolve(__dirname, '../../.env') });

type SignalMessage = {
  sessionId?: string;
  type?: 'offer' | 'ice';
  payload?: any;
};

class SessionManager {
  private sessions = new Map<string, Session>();

  create(sessionId: string) {
    const existing = this.sessions.get(sessionId);
    if (existing) {
      existing.close();
    }
    console.log(`[signal] creating session ${sessionId}`);
    const session = new Session(sessionId, process.env, () => this.sessions.delete(sessionId));
    this.sessions.set(sessionId, session);
    return session;
  }

  get(sessionId: string) {
    return this.sessions.get(sessionId);
  }

  get size() {
    return this.sessions.size;
  }
}

class Session {
  private pc: wrtc.RTCPeerConnection;
  private dc?: RTCDataChannel;
  private stt?: AssemblyAIStreamingSTT;
  private llm?: DeepInfraLLM;
  private ttsRouter?: SmartTTSRouter;
  private llmAbort?: AbortController;
  private destroyed = false;
  private pendingSpeech = '';
  private lastFinalTranscript = '';

  constructor(private id: string, private env: NodeJS.ProcessEnv, private onDestroy: () => void) {
    this.pc = new wrtc.RTCPeerConnection({
      iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
    });
    this.pc.ondatachannel = (event) => void this.handleDataChannel(event.channel);
    this.pc.onconnectionstatechange = () => {
      const state = this.pc.connectionState;
      if (state === 'closed' || state === 'failed' || state === 'disconnected') {
        this.close();
      }
    };
    this.log('peer connection created');
  }

  private log(message: string, ...args: any[]) {
    console.log(`[session:${this.id}] ${message}`, ...args);
  }

  private error(message: string, ...args: any[]) {
    console.error(`[session:${this.id}] ${message}`, ...args);
  }

  async handleOffer(desc: RTCSessionDescriptionInit) {
    this.log('handling offer');
    await this.pc.setRemoteDescription(desc);
    const answer = await this.pc.createAnswer();
    await this.pc.setLocalDescription(answer);
    await this.waitForIceGathering();
    const local = this.pc.localDescription;
    if (!local) throw new Error('Failed to produce local description');
    return local;
  }

  async addIceCandidate(candidate?: RTCIceCandidateInit) {
    if (!candidate) return;
    this.log('adding ice candidate', candidate.sdpMid);
    await this.pc.addIceCandidate(candidate);
  }

  close() {
    if (this.destroyed) return;
    this.destroyed = true;
    this.abortAll();
    try {
      this.dc?.close();
    } catch {}
    try {
      this.pc.close();
    } catch {}
    this.onDestroy();
    this.log('session destroyed');
  }

  private async waitForIceGathering() {
    if (this.pc.iceGatheringState === 'complete') return;
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pc.removeEventListener('icegatheringstatechange', listener);
        console.warn(`[session:${this.id}] ICE gathering timeout, continuing with partial candidates`);
        resolve();
      }, 8000);
      const listener = () => {
        if (this.pc.iceGatheringState === 'complete') {
          clearTimeout(timer);
          this.pc.removeEventListener('icegatheringstatechange', listener);
          resolve();
        }
      };
      this.pc.addEventListener('icegatheringstatechange', listener);
    });
  }

  private async handleDataChannel(channel: RTCDataChannel) {
    this.dc = channel;
    channel.onmessage = (m) => this.handleMessage(m.data);
    channel.onclose = () => this.close();
    this.log('datachannel opened');

    this.stt = new AssemblyAIStreamingSTT(this.env.ASSEMBLYAI_API_KEY ?? '');
    this.stt.onPartialText((text) => {
      this.log('STT partial', text.length);
      this.emit({ type: 'stt.partial', text });
    });
    this.stt.onFinalText((text) => {
      this.log('STT final', text.trim().substring(0, Math.min(64, text.length)));
      void this.handleFinalTranscript(text);
    });
    this.log('starting STT websocket');
    try {
      await this.stt.start();
      this.log('STT websocket ready');
    } catch (error) {
      this.error('STT failed to start', error);
      this.close();
      return;
    }

    this.llm = new DeepInfraLLM(this.env.DEEPINFRA_API_KEY ?? '');
    this.ttsRouter = new SmartTTSRouter(sharedDurableState, this.env, this.buildProviders());
    this.ttsRouter.setHooks({
      onProviderSelected: (name) => this.emit({ type: 'tts.provider', name } as any),
      onTTFA: (name, ms) => this.emit({ type: 'metrics.ttfa', provider: name, ms } as any)
    });
    this.ttsRouter.onAudio((audio) => {
      this.log('TTS audio', audio.byteLength);
      const chunk = Buffer.from(audio);
      this.log('TTS audio chunk', chunk.byteLength);
      this.emit({ type: 'tts.audio', data: chunk.toString('base64'), sampleRate: AUDIO_SAMPLE_RATE });
    });
    this.log('starting TTS router');
    try {
      await this.ttsRouter.start();
      this.log('TTS router ready');
    } catch (error) {
      this.error('TTS router failed to start', error);
      this.close();
      return;
    }

    const active = this.ttsRouter.getActiveName();
    if (active) {
      this.emit({ type: 'tts.provider', name: active } as any);
    }
  }

  private buildProviders() {
    const parseCost = (value: string | undefined, fallback: number) => {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : fallback;
    };
    return [
      {
        name: 'polly',
        impl: new PollyStreamingTTS(this.env.AWS_REGION, this.env.AWS_ACCESS_KEY_ID, this.env.AWS_SECRET_ACCESS_KEY),
        costScore: parseCost(this.env.COST_POLLY, 0.6)
      },
        {
          name: 'elevenlabs',
          impl: new ElevenLabsStreamingTTS(
            this.env.ELEVENLABS_API_KEY,
            this.env.ELEVENLABS_VOICE_ID ?? 'EXAVITQu4vr4xnSDxMaL',
            this.env.ELEVENLABS_MODEL_ID ?? 'eleven_turbo_v2_5',
            this.env.ELEVENLABS_OUTPUT_FORMAT ?? 'pcm_24000',
            (this.env.ELEVENLABS_USE_HTTP ?? '').toLowerCase() === 'true'
          ),
          costScore: parseCost(this.env.COST_ELEVENLABS, 0.35)
        },
        {
          name: 'deepgram',
          impl: new DeepgramStreamingTTS(
            this.env.DEEPGRAM_API_KEY ?? '',
            this.env.DEEPGRAM_MODEL ?? 'aura-asteria-en',
            this.env.DEEPGRAM_ENCODING ?? 'linear16',
            Number(this.env.DEEPGRAM_SAMPLE_RATE ?? 24000),
            this.env.DEEPGRAM_VOICE ?? 'alloy',
            (this.env.DEEPGRAM_USE_HTTP ?? '').toLowerCase() === 'true'
          ),
          costScore: parseCost(this.env.COST_DEEPGRAM, 2.0)
        }
    ];
  }

  async testTts(text: string) {
    if (!this.ttsRouter) {
      throw new Error('TTS router not ready');
    }
    this.log('manual TTS test send', text);
    await this.ttsRouter.sendText(text);
    this.log('manual TTS test acknowledged');
  }

  private async flushPendingSpeech() {
    const candidate = this.pendingSpeech.trim();
    if (candidate.length === 0) return;
    this.pendingSpeech = '';
    this.log('flushing pending speech at stream end', candidate);
    await this.ttsRouter?.sendText(candidate);
    this.log('tts router acknowledged sentence');
  }

  private handleMessage(payload: string | ArrayBuffer | Blob) {
    if (!this.stt) return;
    if (typeof payload !== 'string') return;
    let evt: ProtocolEvent | undefined;
    try {
      evt = JSON.parse(payload);
    } catch {
      return;
    }
    this.log('received datachannel event', evt.type);
    if (evt.type === 'audio_in' && Array.isArray(evt.data)) {
      this.log('audio chunk length', evt.data.length);
    }
    if (evt.type === 'audio_in' && Array.isArray(evt.data)) {
      const buffer = this.chunkToArrayBuffer(evt.data);
      if (buffer) this.stt.sendAudio(buffer);
    }
    if (evt.type === 'cancel') {
      this.log('cancel requested');
      this.abortAll();
    }
  }

  private async handleFinalTranscript(text: string) {
    const trimmed = (text ?? '').toString().trim();
    if (trimmed.length === 0) return;
    if (trimmed === this.lastFinalTranscript) {
      this.log('final transcript duplicate ignored', trimmed);
      return;
    }
    this.lastFinalTranscript = trimmed;
    this.log('final transcript', trimmed);
    this.emit({ type: 'stt.final', text: trimmed });
    this.llmAbort?.abort();
    this.llmAbort = new AbortController();
    try {
      this.log('starting LLM stream for text', trimmed);
      await this.llm?.stream(
        trimmed,
        async (delta) => {
          const raw = (delta ?? '').toString();
          const deltaText = extractDeltaText(raw);
          this.log('llm delta', deltaText);
          this.emit({ type: 'llm.delta', text: deltaText });
          if (deltaText.length === 0) {
            this.log('zero-length delta, buffering for punctuation');
            return;
          }
          this.pendingSpeech += deltaText;
          const trimmed = deltaText.trim();
          const shouldFlush = trimmed.length > 0 && /[.?!]$/.test(trimmed);
          if (!shouldFlush) {
            this.log('pending speech buffer', this.pendingSpeech);
            return;
          }
          const candidate = this.pendingSpeech.trim();
          this.pendingSpeech = '';
          if (candidate.length === 0) return;
      this.log('flushing sentence to TTS router', candidate);
      try {
        await this.ttsRouter?.sendText(candidate);
        this.log('tts router acknowledged sentence');
      } catch (error) {
        this.error('tts router sendText failed', error);
      }
        },
        async () => {
          this.emit({ type: 'llm.final' });
          await this.flushPendingSpeech();
          this.log('LLM stream completed');
        },
        this.llmAbort.signal
      );
    } catch (error) {
      if ((error as Error).name === 'AbortError') return;
      console.warn('LLM stream failed', error);
    }
  }

  private emit(evt: any) {
    if (this.dc?.readyState !== 'open') return;
    this.log('sending event', evt.type);
    try {
      this.dc.send(JSON.stringify(evt));
    } catch {
      // ignore
    }
  }

  private abortAll() {
    this.log('aborting STT/LLM/TTS');
    this.stt?.close();
    this.llmAbort?.abort();
    this.ttsRouter?.abort();
  }

  private chunkToArrayBuffer(data: number[]) {
    if (!Array.isArray(data) || data.length === 0) return null;
    const buffer = new Int16Array(data.length);
    for (let i = 0; i < data.length; i++) {
      buffer[i] = data[i];
    }
    return buffer.buffer;
  }
}

const manager = new SessionManager();

const corsOptions = {
  origin: (origin: string | undefined, callback: (err: Error | null, allow?: boolean) => void) => {
    callback(null, true);
  },
  methods: ['POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
};
const app = express();
app.use(cors(corsOptions));
app.options('*', cors(corsOptions), (_req, res) => res.sendStatus(204));
app.use(express.json({ limit: '6mb' }));

app.post('/signal', async (req, res) => {
  const { sessionId, type, payload } = req.body as SignalMessage;
  if (!sessionId || !type) {
    return res.status(400).json({ error: 'sessionId and type are required' });
  }

  try {
    if (type === 'offer') {
      console.log(`[signal] offer received for ${sessionId}`);
      const session = manager.create(sessionId);
      const answer = await session.handleOffer(payload);
      return res.json(answer);
    }
    if (type === 'ice') {
      const session = manager.get(sessionId);
      if (!session) {
        return res.status(404).json({ error: 'session not found' });
      }
      await session.addIceCandidate(payload);
      return res.send('ok');
    }
    return res.status(400).json({ error: 'unsupported signal type' });
  } catch (error) {
    console.error(`[signal] error handling ${type} for ${sessionId}`, error);
    return res.status(500).json({ error: 'signal exchange failed' });
  }
});

app.post('/sessions/:id/tts-test', async (req, res) => {
  const sessionId = req.params.id;
  const { text } = req.body as { text?: string };
  const session = manager.get(sessionId);
  if (!session) {
    return res.status(404).json({ error: 'session not found' });
  }
  if (!text || text.trim().length === 0) {
    return res.status(400).json({ error: 'text is required' });
  }
  try {
    await session.testTts(text.trim());
    return res.json({ ok: true });
  } catch (error) {
    console.error(`[signal] tts-test failed for ${sessionId}`, error);
    return res.status(500).json({ error: 'tts test failed' });
  }
});

app.get('/health', (req, res) => {
  res.json({ ok: true, sessions: manager.size });
});

const port = Number(process.env.WEBRTC_PORT ?? process.env.PORT ?? 3001);
const host = process.env.HOST ?? '127.0.0.1';

app.listen(port, host, () => {
  console.log(`WebRTC signal server listening on http://${host}:${port}`);
});
