import 'dotenv/config';
import { SmartTTSRouter } from '../src/router/tts_router.ts';
import { StreamingTTS } from '../src/router/tts_types.ts';
import { ElevenLabsStreamingTTS } from '../src/providers/tts/elevenlabs_ws.ts';

type MemoryStorage = {
  data: Map<string, unknown>;
  get(key: string): Promise<unknown>;
  put(key: string, value: unknown): Promise<void>;
};

class MemoryStorageImpl implements MemoryStorage {
  data = new Map<string, unknown>();
  async get(key: string) {
    return this.data.get(key);
  }
  async put(key: string, value: unknown) {
    this.data.set(key, value);
  }
}

class StubStreamingTTS implements StreamingTTS {
  private audioCb?: (buf: ArrayBuffer) => void;

  async start() {
    console.log('[StubTTS] start');
  }

  async sendText(text: string) {
    console.log('[StubTTS] sendText', text);
    const chunk = Uint8Array.from([0, 1, 2, 3, 4]);
    setTimeout(() => {
      console.log('[StubTTS] emitting audio chunk');
      this.audioCb?.(chunk.buffer);
    }, 150);
  }

  onAudio(cb: (buf: ArrayBuffer) => void) {
    this.audioCb = cb;
  }

  abort() {
    console.log('[StubTTS] abort');
  }
}

async function wait(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function createProvider(name: string): { name: string; impl: StreamingTTS; costScore: number } {
  if (name === 'elevenlabs') {
    const apiKey = process.env.ELEVENLABS_API_KEY;
    if (!apiKey) throw new Error('ELEVENLABS_API_KEY is required for the elevenlabs provider');
    const useHttp = (process.env.ELEVENLABS_USE_HTTP ?? '').toLowerCase() === 'true';
    return {
      name: 'elevenlabs',
      impl: new ElevenLabsStreamingTTS(
        apiKey,
        process.env.ELEVENLABS_VOICE_ID ?? 'EXAVITQu4vr4xnSDxMaL',
        process.env.ELEVENLABS_MODEL_ID ?? 'eleven_turbo_v2_5',
        process.env.ELEVENLABS_OUTPUT_FORMAT ?? 'pcm_24000',
        useHttp
      ),
      costScore: 1,
    };
  }
  return { name: 'stub', impl: new StubStreamingTTS(), costScore: 1 };
}

async function main() {
  const args = process.argv.slice(2);
  const requestedProvider = args[0]?.toLowerCase();
  const providerName = requestedProvider === 'elevenlabs' ? 'elevenlabs' : 'stub';
  const message = args.slice(providerName === requestedProvider ? 1 : 0).join(' ') || 'This is a TTS router smoke test.';

  if (requestedProvider && requestedProvider !== providerName) {
    console.log(`Unknown provider "${requestedProvider}", falling back to stub.`);
  }

  const state = { storage: new MemoryStorageImpl() } as any;
  const providerEntry = createProvider(providerName);
  const router = new SmartTTSRouter(state, process.env, [providerEntry], [providerEntry.name]);

  router.setHooks({
    onProviderSelected: (name) => console.log('[Router] selected', name),
    onTTFA: (name, ms) => console.log('[Router] TTFA', name, ms),
  });

  router.onAudio((chunk) => {
    console.log('[Router] received chunk', chunk.byteLength, 'bytes');
  });

  await router.start();
  await router.sendText(message);
  await wait(1000);
  router.abort();
}

main().catch((err) => {
  console.error('TTS test failed:', err);
  process.exit(1);
});
