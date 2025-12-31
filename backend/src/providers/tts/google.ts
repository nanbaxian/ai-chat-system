export class GoogleTTS {
  constructor(private apiKey: string) {}

  async speak(text: string, onAudio: (buf: ArrayBuffer) => void, abort?: AbortSignal) {
    const res = await fetch(
      `https://texttospeech.googleapis.com/v1/text:synthesize?key=${this.apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          input: { text },
          voice: { languageCode: 'en-US', name: 'en-US-Standard-C' },
          audioConfig: { audioEncoding: 'LINEAR16' }
        }),
        signal: abort
      }
    );

    const json = await res.json();
    const audio = Uint8Array.from(atob(json.audioContent), c => c.charCodeAt(0));
    onAudio(audio.buffer);
  }
}
