// Cloudflare Analytics Engine binding required:
// [[analytics_engine_datasets]]
// binding = "VOICE_METRICS"

export interface MetricRecord {
  sessionId: string;
  userId?: string;
  sttTTFT?: number;
  llmTTFT?: number;
  ttsTTFA?: number;
  e2e?: number;
  interrupts: number;
}

export async function writeMetric(
  env: any,
  record: MetricRecord
) {
  env.VOICE_METRICS.writeDataPoint({
    blobs: [
      record.sessionId,
      record.userId ?? 'anonymous'
    ],
    doubles: [
      record.sttTTFT ?? -1,
      record.llmTTFT ?? -1,
      record.ttsTTFA ?? -1,
      record.e2e ?? -1,
      record.interrupts
    ],
    indexes: [
      'voice-ai',
      new Date().toISOString().slice(0, 10)
    ]
  });
}
