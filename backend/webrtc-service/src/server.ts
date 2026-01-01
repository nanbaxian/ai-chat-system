import path from 'path';
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
  }

  async handleOffer(desc: RTCSessionDescriptionInit) {
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
  }

  private async waitForIceGathering() {
    if (this.pc.iceGatheringState === 'complete') return;
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pc.removeEventListener('icegatheringstatechange', listener);
        reject(new Error('ICE gathering timeout'));
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

    this.stt = new AssemblyAIStreamingSTT(this.env.ASSEMBLYAI_API_KEY ?? '');
    this.stt.onPartialText((text) => this.emit({ type: 'stt.partial', text }));
    this.stt.onFinalText((text) => void this.handleFinalTranscript(text));
    try {
      await this.stt.start();
    } catch (error) {
      console.warn('STT failed to start', error);
      this.close();
      return;
    }

    this.llm = new DeepInfraLLM(this.env.DEEPINFRA_API_KEY ?? '');
    this.ttsRouter = new SmartTTSRouter(sharedDurableState, this.env, this.buildProviders());
    this.ttsRouter.setHooks({
      onProviderSelected: (name) => this.emit({ type: 'tts.provider', name } as any),
      onTTFA: (name, ms) => this.emit({ type: 'metrics.ttfa', provider: name, ms } as any)
    });
    this.ttsRouter.onAudio((audio) => this.emit({ type: 'tts.audio', data: audio }));
    try {
      await this.ttsRouter.start();
    } catch (error) {
      console.warn('TTS router failed to start', error);
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
          this.env.ELEVENLABS_OUTPUT_FORMAT ?? 'pcm_24000'
        ),
        costScore: parseCost(this.env.COST_ELEVENLABS, 1.3)
      },
      {
        name: 'deepgram',
        impl: new DeepgramStreamingTTS(
          this.env.DEEPGRAM_API_KEY ?? '',
          this.env.DEEPGRAM_MODEL ?? 'aura-asteria-en',
          this.env.DEEPGRAM_ENCODING ?? 'linear16',
          Number(this.env.DEEPGRAM_SAMPLE_RATE ?? 24000)
        ),
        costScore: parseCost(this.env.COST_DEEPGRAM, 0.9)
      }
    ];
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
    if (evt.type === 'audio_in' && Array.isArray(evt.data)) {
      const buffer = this.chunkToArrayBuffer(evt.data);
      if (buffer) this.stt.sendAudio(buffer);
    }
    if (evt.type === 'cancel') {
      this.abortAll();
    }
  }

  private async handleFinalTranscript(text: string) {
    const trimmed = (text ?? '').toString().trim();
    if (trimmed.length === 0) return;
    this.emit({ type: 'stt.final', text: trimmed });
    await this.ttsRouter?.sendText('Hmm.');
    this.llmAbort?.abort();
    this.llmAbort = new AbortController();
    try {
      await this.llm?.stream(
        trimmed,
        async (delta) => {
          this.emit({ type: 'llm.delta', text: delta });
          await this.ttsRouter?.sendText(delta);
        },
        () => {
          this.emit({ type: 'llm.final' });
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
    try {
      this.dc.send(JSON.stringify(evt));
    } catch {
      // ignore
    }
  }

  private abortAll() {
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

const app = express();
app.use(cors());
app.use(express.json({ limit: '6mb' }));

app.post('/signal', async (req, res) => {
  const { sessionId, type, payload } = req.body as SignalMessage;
  if (!sessionId || !type) {
    return res.status(400).json({ error: 'sessionId and type are required' });
  }

  try {
    if (type === 'offer') {
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
    console.error('signal error', error);
    return res.status(500).json({ error: 'signal exchange failed' });
  }
});

app.get('/health', (req, res) => {
  res.json({ ok: true, sessions: manager.size });
});

const port = Number(process.env.WEBRTC_PORT ?? process.env.PORT ?? 3001);
app.listen(port, () => {
  console.log(`WebRTC signal server listening on port ${port}`);
});
