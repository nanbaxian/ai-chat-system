export type Event =
 | { type: 'audio_in'; data: ArrayBuffer }
 | { type: 'tts.audio'; data: ArrayBuffer }
 | { type: 'cancel' };
