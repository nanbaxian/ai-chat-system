import { Event } from '../protocol/events.ts';
import { AssemblyAIStreamingSTT } from '../providers/stt/assemblyai.ts';
import { DeepInfraLLM } from '../providers/llm/deepinfra.ts';
import { PollyStreamingTTS } from '../providers/tts/polly_streaming.ts';
import { ElevenLabsStreamingTTS } from '../providers/tts/elevenlabs_ws.ts';
import { DeepgramStreamingTTS } from '../providers/tts/deepgram_ws.ts';
import { SmartTTSRouter } from '../router/tts_router.ts';

export class SessionDO {
  pc: RTCPeerConnection | null = null;
  dc: RTCDataChannel | null = null;

  stt?: AssemblyAIStreamingSTT;
  llm?: DeepInfraLLM;
  ttsRouter?: SmartTTSRouter;
  llmAbort?: AbortController;

  constructor(private state: DurableObjectState, private env: any) {}

  async fetch(req: Request) {
    const url = new URL(req.url);

    // Optional debug: GET /debug returns current router stats
    if (req.method === 'GET' && url.pathname.endsWith('/debug')) {
      return new Response(JSON.stringify(this.ttsRouter?.getDebugSnapshot?.() ?? { active: null }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const body = await req.json().catch(() => ({ type: null, payload: null }));
    const { type, payload } = body ?? { type: null, payload: null };

    if (!this.pc) await this.initPC();

    if (type === 'offer') {
      await this.pc!.setRemoteDescription(payload);
      const ans = await this.pc!.createAnswer();
      await this.pc!.setLocalDescription(ans);
      return new Response(JSON.stringify(ans), { headers: { 'Content-Type': 'application/json' } });
    }

    if (type === 'ice') {
      await this.pc!.addIceCandidate(payload);
      return new Response('ok');
    }

    return new Response('noop');
  }

  async initPC() {
    this.pc = new RTCPeerConnection({
      iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
    });

    this.pc.ondatachannel = async (e) => {
      this.dc = e.channel;

      // STT
      this.stt = new AssemblyAIStreamingSTT(this.env.ASSEMBLYAI_API_KEY);
      await this.stt.start();

      // LLM
      this.llm = new DeepInfraLLM(this.env.DEEPINFRA_API_KEY);

      // Smart Router: latency / cost / failure aware
      this.ttsRouter = new SmartTTSRouter(this.state, this.env, [
        { name: 'polly', impl: new PollyStreamingTTS(this.env.AWS_REGION, this.env.AWS_ACCESS_KEY_ID, this.env.AWS_SECRET_ACCESS_KEY), costScore: Number(this.env.COST_POLLY ?? 0.6) },
        { name: 'elevenlabs', impl: new ElevenLabsStreamingTTS(this.env.ELEVENLABS_API_KEY, this.env.ELEVENLABS_VOICE_ID ?? 'EXAVITQu4vr4xnSDxMaL', this.env.ELEVENLABS_MODEL_ID ?? 'eleven_turbo_v2_5', this.env.ELEVENLABS_OUTPUT_FORMAT ?? 'pcm_24000'), costScore: Number(this.env.COST_ELEVENLABS ?? 1.3) },
        { name: 'deepgram', impl: new DeepgramStreamingTTS(this.env.DEEPGRAM_API_KEY, this.env.DEEPGRAM_MODEL ?? 'aura-asteria-en', this.env.DEEPGRAM_ENCODING ?? 'linear16', Number(this.env.DEEPGRAM_SAMPLE_RATE ?? 24000)), costScore: Number(this.env.COST_DEEPGRAM ?? 0.9) },
      ]);

      // Hook router telemetry to UI
      this.ttsRouter.setHooks({
        onProviderSelected: (name) => this.emit({ type: 'tts.provider', name } as any),
        onTTFA: (name, ms) => this.emit({ type: 'metrics.ttfa', provider: name, ms } as any),
      });

      this.ttsRouter.onAudio((audio) => this.emit({ type: 'tts.audio', data: audio }));
      await this.ttsRouter.start();

      // Send initial provider to UI (in case hooks fired before DC listener ready)
      const active = this.ttsRouter.getActiveName();
      if (active) this.emit({ type: 'tts.provider', name: active } as any);

      this.stt.onFinalText(async (text) => {
        // Latency masking
        await this.ttsRouter!.sendText('Hmm.');

        this.llmAbort = new AbortController();

        await this.llm!.stream(
          text,
          async (delta) => {
            this.emit({ type: 'llm.delta', text: delta });
            await this.ttsRouter!.sendText(delta);
          },
          async () => {},
          this.llmAbort!.signal
        );
      });

      this.dc!.onmessage = (m) => {
        const evt: Event = JSON.parse(m.data);
        if (evt.type === 'audio_in') this.stt?.sendAudio(evt.data);
        if (evt.type === 'cancel') this.abortAll();
      };
    };
  }

  abortAll() {
    this.stt?.close();
    this.llmAbort?.abort();
    this.ttsRouter?.abort();
  }

  emit(evt: any) {
    this.dc?.send(JSON.stringify(evt));
  }
}
