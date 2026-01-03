import { StreamingTTS } from './tts_types.ts';
import { TTSMetrics, TTSCost, TTSStats } from '../metrics/tts_metrics.ts';

export type TTSProviderEntry = {
  name: string;
  impl: StreamingTTS;
  costScore: number; // relative weight (lower = cheaper)
};

export class SmartTTSRouter {
  private active?: TTSProviderEntry;
  private audioCb?: (buf: ArrayBuffer) => void;

  private stats: TTSStats = {};
  private costs: TTSCost = {};

  private sendStartedAt?: number;
  private firstAudioSeen = false;
  private lastTTFAMs?: number;

  private metrics: TTSMetrics;

  private preferenceOrder: string[];

  // hooks for UI/debug telemetry over DataChannel
  private onProviderSelected?: (name: string) => void;
  private onTTFA?: (name: string, ms: number) => void;

  constructor(
    private state: DurableObjectState,
    private env: any,
    private providers: TTSProviderEntry[],
    preferredOrder?: string[]
  ) {
    for (const p of providers) this.costs[p.name] = { costScore: p.costScore };
    this.metrics = new TTSMetrics(state, env, this.costs);
    this.preferenceOrder =
      preferredOrder?.length && preferredOrder.every((name) => name.trim().length > 0)
        ? preferredOrder.map((name) => name.trim())
        : this.parsePreferredOrder(env) ??
          ['elevenlabs', 'polly', 'deepgram'];
  }

  setHooks(h: { onProviderSelected?: (name: string) => void; onTTFA?: (name: string, ms: number) => void }) {
    this.onProviderSelected = h.onProviderSelected;
    this.onTTFA = h.onTTFA;
  }

  getActiveName() {
    return this.active?.name ?? null;
  }

  getLastTTFAMs() {
    return this.lastTTFAMs ?? null;
  }

  async start() {
    this.stats = await this.metrics.load();

    const ranked = [...this.providers].sort((a, b) => this.scoreWithPreference(a) - this.scoreWithPreference(b));

    for (const p of ranked) {
      try {
        console.log(`SmartTTSRouter: attempting to start ${p.name}`);
        await p.impl.start();
        this.active = p;
        if (this.audioCb) p.impl.onAudio(this.wrapAudioCb(p.name));
        this.metrics.writeAE('tts.select', { provider: p.name, ok: true, costScore: p.costScore });
        this.onProviderSelected?.(p.name);
        await this.metrics.save(this.stats);
        console.log(`SmartTTSRouter: provider ${p.name} selected`);
        return;
      } catch (error) {
        console.error(`SmartTTSRouter: provider ${p.name} start failed`, error);
        this.metrics.markFailure(this.stats, p.name);
        this.metrics.writeAE('tts.start_fail', { provider: p.name, ok: false, costScore: p.costScore });
      }
    }

    await this.metrics.save(this.stats);
    throw new Error('No TTS provider available');
  }

  onAudio(cb: (buf: ArrayBuffer) => void) {
    console.log(`onAudio:`+cb);
    this.audioCb = cb;
    if (this.active) {
      console.log(`active:`+this.active.name);
      this.active.impl.onAudio(this.wrapAudioCb(this.active.name));
      console.log(`real audio:`);
    }
  }

  private wrapAudioCb(providerName: string) {
    return (buf: ArrayBuffer) => {
      console.log(`SmartTTSRouter: audio chunk from ${providerName} length=${buf.byteLength}`);
      if (!this.firstAudioSeen && this.sendStartedAt) {
        this.firstAudioSeen = true;
        const ms = Date.now() - this.sendStartedAt;
        this.lastTTFAMs = ms;

        this.metrics.updateEwma(this.stats, providerName, ms);
        this.metrics.markSuccess(this.stats, providerName);
        this.metrics.writeAE('tts.ttfa_ms', { provider: providerName, valueMs: ms, ok: true, costScore: this.costs[providerName]?.costScore });
        this.onTTFA?.(providerName, ms);

        // fire-and-forget save
        this.metrics.save(this.stats);
      }
      this.audioCb?.(buf);
    };
  }

  async sendText(text: string) {
    if (!this.active) throw new Error('No active TTS provider');
    if (!this.sendStartedAt) {
      this.sendStartedAt = Date.now();
      this.firstAudioSeen = false;
      this.lastTTFAMs = undefined;
    }
      try {
        console.log(`SmartTTSRouter: sending text to ${this.active.name}`);
        await this.active.impl.sendText(text);
        console.log(`SmartTTSRouter: sendText succeeded for ${this.active.name}`);
    } catch {
      console.error(`SmartTTSRouter: sendText failed for ${this.active.name}`);
      // mark failure + switch to next best and retry once
      this.metrics.markFailure(this.stats, this.active.name);
      this.metrics.writeAE('tts.send_fail', { provider: this.active.name, ok: false, costScore: this.active.costScore });

      try { this.active.impl.abort(); } catch {}

      const ranked = [...this.providers]
        .filter(p => p.name !== this.active!.name)
        .sort((a, b) => this.scoreWithPreference(a) - this.scoreWithPreference(b));

      for (const p of ranked) {
        try {
          console.log(`SmartTTSRouter: failover starting provider ${p.name}`);
          await p.impl.start();
          this.active = p;
          if (this.audioCb) p.impl.onAudio(this.wrapAudioCb(p.name));
          this.metrics.writeAE('tts.failover', { provider: p.name, ok: true, costScore: p.costScore });
          this.onProviderSelected?.(p.name);
          await this.active.impl.sendText(text);
          console.log(`SmartTTSRouter: failover sendText succeeded for ${p.name}`);
          await this.metrics.save(this.stats);
          return;
        } catch {
          console.error(`SmartTTSRouter: failover failed for provider ${p.name}`);
          this.metrics.markFailure(this.stats, p.name);
          this.metrics.writeAE('tts.failover_fail', { provider: p.name, ok: false, costScore: p.costScore });
        }
      }
      console.log(`save metrics`);
      await this.metrics.save(this.stats);
      throw new Error('Failover exhausted');
    }
  }

  abort() {
    console.log(`abort`);
    try { this.active?.impl.abort(); } catch {}
    this.sendStartedAt = undefined;
    this.firstAudioSeen = false;
    this.lastTTFAMs = undefined;
  }

  getDebugSnapshot() {
    console.log(`getDebugSnapshot`);
    return {
      active: this.active?.name,
      lastTTFAMs: this.lastTTFAMs,
      stats: this.stats,
      ranked: [...this.providers].map(p => ({
        name: p.name,
        score: this.metrics.score(this.stats, p.name),
        costScore: p.costScore,
        ewmaFirstAudioMs: this.stats[p.name]?.ewmaFirstAudioMs,
        failures: this.stats[p.name]?.failures,
        successes: this.stats[p.name]?.successes,
      })).sort((a,b)=>a.score-b.score)
    };
  }

  private scoreWithPreference(entry: TTSProviderEntry) {
    console.log(`scoreWithPreference`);
    return this.metrics.score(this.stats, entry.name) + this.preferenceBias(entry.name) * 3000;
  }

  private preferenceBias(name: string) {
    console.log(`preferenceBias`);
    const idx = this.preferenceOrder.indexOf(name);
    return idx >= 0 ? idx : this.preferenceOrder.length;
  }

  private parsePreferredOrder(env: any): string[] | undefined {
    console.log(`parsePreferredOrder`);
    const raw = env.PREFERRED_TTS_ORDER ?? env.PREFERRED_TTS;
    if (!raw || typeof raw !== 'string') return undefined;
    const parsed = raw
      .split(',')
      .map((name) => name.trim())
      .filter((name) => name.length > 0);
    return parsed.length ? parsed : undefined;
  }
}
