import { writeMetric } from '../metrics/analytics';

export async function flushMetrics(env: any, sessionId: string, metrics: any, userId?: string) {
  await writeMetric(env, {
    sessionId,
    userId,
    sttTTFT: metrics.sttFirstToken,
    llmTTFT: metrics.llmFirstToken,
    ttsTTFA: metrics.ttsFirstAudio,
    e2e: Date.now() - metrics.startTime,
    interrupts: metrics.interrupts,
  });
}
