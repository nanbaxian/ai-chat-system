export interface StreamingTTS {
  start(): Promise<void>;
  sendText(text: string): void;
  onAudio(cb: (buf: ArrayBuffer) => void): void;
  abort(): void;
}
