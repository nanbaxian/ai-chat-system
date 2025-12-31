import fetch from 'node-fetch';
import { StreamingTTS } from '../../router/tts_types';

export class DeepgramTTS implements StreamingTTS {
  private cb?: (buf: ArrayBuffer) => void;
  constructor(private apiKey: string) {}

  async start() {}

  async sendText(text: string) {
    const res = await fetch('https://api.deepgram.com/v1/speak?model=aura-asteria-en', {
      method: 'POST',
      headers: {
        'Authorization': `Token ${this.apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ text })
    });

    const buf = await res.arrayBuffer();
    this.cb?.(buf);
  }

  onAudio(cb: (buf: ArrayBuffer) => void) {
    this.cb = cb;
  }

  abort() {}
}
