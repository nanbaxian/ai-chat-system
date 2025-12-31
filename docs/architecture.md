# Architecture Overview

Flutter
 → WebRTC (Audio + DataChannel)
 → Cloudflare Worker (Signaling)
 → Durable Object (Session = Orchestrator)
 → STT / LLM / TTS (Router + Providers)
 → Metrics (Analytics Engine)
 → Billing Engine
 → Stripe
