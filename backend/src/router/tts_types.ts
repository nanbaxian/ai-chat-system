export interface StreamingTTS {
  start(): Promise<void>;
  sendText(text: string): Promise<void>;
  onAudio(cb: (buf: ArrayBuffer) => void): void;
  abort(): void;
}
