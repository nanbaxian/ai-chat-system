import 'dotenv/config';
import { DeepgramStreamingTTS } from '../src/providers/tts/deepgram_ws.ts';

async function wait(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  const args = process.argv.slice(2);
  const message = args.join(' ') || 'Deepgram TTS sanity check.';
  const apiKey = process.env.DEEPGRAM_API_KEY;
  if (!apiKey) {
    throw new Error('DEEPGRAM_API_KEY is required to test Deepgram TTS');
  }

  const useHttp = (process.env.DEEPGRAM_USE_HTTP ?? '').toLowerCase() === 'true';
  const provider = new DeepgramStreamingTTS(
    apiKey,
    process.env.DEEPGRAM_MODEL ?? 'aura-asteria-en',
    process.env.DEEPGRAM_ENCODING ?? 'linear16',
    Number(process.env.DEEPGRAM_SAMPLE_RATE ?? 24000),
    process.env.DEEPGRAM_VOICE ?? 'alloy',
    useHttp
  );

  provider.onAudio((buf) => {
    console.log(`[Deepgram] received chunk ${buf.byteLength} bytes`);
  });

  try {
    console.log('[Deepgram] starting');
    await provider.start();
    console.log('[Deepgram] sending text', message);
    await provider.sendText(message);
    await wait(2000);
  } finally {
    console.log('[Deepgram] closing');
    provider.abort();
  }
}

main().catch((err) => {
  console.error('Deepgram test failed:', err);
  process.exit(1);
});
