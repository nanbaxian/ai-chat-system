type TTSProviderName = 'polly' | 'elevenlabs' | 'deepgram' | string;

export type TTSStats = Record<TTSProviderName, {
  ewmaFirstAudioMs?: number;   // rolling average of time-to-first-audio
  failures?: number;
  successes?: number;
  lastErrorAt?: number;
  lastSuccessAt?: number;
}>;

export type TTSCost = Record<TTSProviderName, {
  // Relative cost weight (not exact billing). You can tune later.
  // Example: dollars per 1M chars or a normalized cost score.
  costScore: number;
}>;

export class TTSMetrics {
  constructor(
    private state: DurableObjectState,
    private env: any,
    private costs: TTSCost
  ) {}

  async load(): Promise<TTSStats> {
    const v = await this.state.storage.get('tts_stats');
    return (v as TTSStats) ?? {};
  }

  async save(stats: TTSStats) {
    await this.state.storage.put('tts_stats', stats);
  }

  private ensure(stats: TTSStats, name: TTSProviderName) {
    stats[name] ??= {};
    stats[name].failures ??= 0;
    stats[name].successes ??= 0;
  }

  updateEwma(stats: TTSStats, name: TTSProviderName, firstAudioMs: number, alpha = 0.2) {
    this.ensure(stats, name);
    const cur = stats[name].ewmaFirstAudioMs;
    stats[name].ewmaFirstAudioMs = cur == null ? firstAudioMs : (alpha * firstAudioMs + (1 - alpha) * cur);
  }

  markFailure(stats: TTSStats, name: TTSProviderName) {
    this.ensure(stats, name);
    stats[name].failures! += 1;
    stats[name].lastErrorAt = Date.now();
  }

  markSuccess(stats: TTSStats, name: TTSProviderName) {
    this.ensure(stats, name);
    stats[name].successes! += 1;
    stats[name].lastSuccessAt = Date.now();
  }

  // Score = latency + failure penalty + cost
  score(stats: TTSStats, name: TTSProviderName) {
    this.ensure(stats, name);
    const s = stats[name];
    const latency = s.ewmaFirstAudioMs ?? 650; // default assumption (ms)
    const total = (s.successes ?? 0) + (s.failures ?? 0);
    const failRate = total > 0 ? (s.failures ?? 0) / total : 0.05;
    const cost = this.costs[name]?.costScore ?? 1.0;

    // weights (tune)
    const wLatency = 1.0;          // 1 ms = 1 point
    const wFail = 1500.0;          // failRate * 1500 points
    const wCost = 120.0;           // costScore * 120 points

    return (wLatency * latency) + (wFail * failRate) + (wCost * cost);
  }

  // Write a datapoint into Cloudflare Analytics Engine if available.
  writeAE(kind: string, data: { provider: string; valueMs?: number; ok?: boolean; costScore?: number }) {
    try {
      if (!this.env.VOICE_METRICS?.writeDataPoint) return;
      this.env.VOICE_METRICS.writeDataPoint({
        blobs: [kind, data.provider],
        doubles: [
          data.valueMs ?? -1,
          data.ok === undefined ? -1 : (data.ok ? 1 : 0),
          data.costScore ?? -1
        ],
        indexes: [kind, data.provider]
      });
    } catch {
      // ignore
    }
  }
}
