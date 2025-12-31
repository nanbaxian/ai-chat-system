# Voice AI Platform – Final Merged Demo Repo

This is the **final merged** runnable repository including:
- Cloudflare Worker + Durable Object session (WebRTC signaling, STT/LLM/TTS orchestration)
- Providers: AssemblyAI STT, DeepInfra LLM (+ OpenAI fallback hooks), TTS: Polly/ElevenLabs/Deepgram via true streaming WS (router + smart metrics)
- Router + circuit-break / failover (STT/TTS/LLM)
- Auth / quota / billing skeleton (Stripe-ready)
- Metrics: TTFT / latency / interrupt + Cloudflare Analytics Engine storage
- Flutter frontend (WebRTC, DataChannel, chat UI, thinking + fake waveform, interrupt/barge-in)

## Repo structure
- `backend/` Cloudflare Worker + Durable Objects
- `frontend/` Flutter (Web, iOS, Android)

## Quick start
### Backend
1. `cd backend`
2. `cp ENV.md .dev.vars` and fill keys
3. `npm i`
4. `npx wrangler dev`

### Frontend (Flutter)
1. `cd frontend/flutter`
2. `flutter pub get`
3. `flutter run -d chrome` (or android/ios)

## Notes
- This repo is demo-grade but fully runnable end-to-end.
- For production, tighten SigV4 signing for Polly, add R2/DB persistence, and enforce billing/quota server-side.


## UI additions (ChatGPT Voice style)
- Shows active TTS provider (selected by SmartTTSRouter)
- Live TTFA (time-to-first-audio) in AppBar and assistant bubble footer
- 'Speaking' hint while audio is streaming
