import { PricingTable, Plan } from './pricing';

export function checkQuota(plan: Plan, usage: any) {
  const p = PricingTable[plan];
  return {
    stt: usage.sttMs / 60000 < p.sttMinutes,
    tts: usage.ttsChars < p.ttsChars,
    llm: usage.llmTokens < p.llmTokens,
  };
}
