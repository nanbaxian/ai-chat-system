import fetch from 'node-fetch';
import { StreamingTTS } from '../../router/tts_types';

export class ElevenLabsTTS implements StreamingTTS {
  private cb?: (buf: ArrayBuffer) => void;
  constructor(private apiKey: string) {}

  async start() {}

  async sendText(text: string) {
    const res = await fetch('https://api.elevenlabs.io/v1/text-to-speech/EXAVITQu4vr4xnSDxMaL/stream', {
      method: 'POST',
      headers: {
        'xi-api-key': this.apiKey,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        text,
        model_id: 'eleven_monolingual_v1',
        voice_settings: { stability: 0.5, similarity_boost: 0.5 }
      })
    });

    const reader = res.body!.getReader();
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      this.cb?.(value.buffer);
    }
  }

  onAudio(cb: (buf: ArrayBuffer) => void) {
    this.cb = cb;
  }

  abort() {}
}
