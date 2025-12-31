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

  // hooks for UI/debug telemetry over DataChannel
  private onProviderSelected?: (name: string) => void;
  private onTTFA?: (name: string, ms: number) => void;

  constructor(
    private state: DurableObjectState,
    private env: any,
    private providers: TTSProviderEntry[]
  ) {
    for (const p of providers) this.costs[p.name] = { costScore: p.costScore };
    this.metrics = new TTSMetrics(state, env, this.costs);
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

    const ranked = [...this.providers].sort((a, b) =>
      this.metrics.score(this.stats, a.name) - this.metrics.score(this.stats, b.name)
    );

    for (const p of ranked) {
      try {
        await p.impl.start();
        this.active = p;
        if (this.audioCb) p.impl.onAudio(this.wrapAudioCb(p.name));
        this.metrics.writeAE('tts.select', { provider: p.name, ok: true, costScore: p.costScore });
        this.onProviderSelected?.(p.name);
        await this.metrics.save(this.stats);
        return;
      } catch {
        this.metrics.markFailure(this.stats, p.name);
        this.metrics.writeAE('tts.start_fail', { provider: p.name, ok: false, costScore: p.costScore });
      }
    }

    await this.metrics.save(this.stats);
    throw new Error('No TTS provider available');
  }

  onAudio(cb: (buf: ArrayBuffer) => void) {
    this.audioCb = cb;
    if (this.active) this.active.impl.onAudio(this.wrapAudioCb(this.active.name));
  }

  private wrapAudioCb(providerName: string) {
    return (buf: ArrayBuffer) => {
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
      await (this.active.impl as any).sendText(text);
    } catch {
      // mark failure + switch to next best and retry once
      this.metrics.markFailure(this.stats, this.active.name);
      this.metrics.writeAE('tts.send_fail', { provider: this.active.name, ok: false, costScore: this.active.costScore });

      try { this.active.impl.abort(); } catch {}

      const ranked = [...this.providers]
        .filter(p => p.name !== this.active!.name)
        .sort((a, b) => this.metrics.score(this.stats, a.name) - this.metrics.score(this.stats, b.name));

      for (const p of ranked) {
        try {
          await p.impl.start();
          this.active = p;
          if (this.audioCb) p.impl.onAudio(this.wrapAudioCb(p.name));
          this.metrics.writeAE('tts.failover', { provider: p.name, ok: true, costScore: p.costScore });
          this.onProviderSelected?.(p.name);
          await (this.active.impl as any).sendText(text);
          await this.metrics.save(this.stats);
          return;
        } catch {
          this.metrics.markFailure(this.stats, p.name);
          this.metrics.writeAE('tts.failover_fail', { provider: p.name, ok: false, costScore: p.costScore });
        }
      }

      await this.metrics.save(this.stats);
      throw new Error('Failover exhausted');
    }
  }

  abort() {
    try { this.active?.impl.abort(); } catch {}
    this.sendStartedAt = undefined;
    this.firstAudioSeen = false;
    this.lastTTFAMs = undefined;
  }

  getDebugSnapshot() {
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
}
