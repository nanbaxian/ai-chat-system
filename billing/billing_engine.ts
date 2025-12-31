import { PricingTable, Plan } from './pricing';
import { UsageRecord } from './usage';

export function calculateBill(plan: Plan, usage: UsageRecord) {
  const p = PricingTable[plan];
  const sttMinutes = usage.sttMs / 60000;

  let cost = 0;

  if (sttMinutes > p.sttMinutes) {
    cost += (sttMinutes - p.sttMinutes) * p.pricePerExtraSTTMinute;
  }

  if (usage.ttsChars > p.ttsChars) {
    cost += ((usage.ttsChars - p.ttsChars) / 1000) * p.pricePerExtraTTS1k;
  }

  if (usage.llmTokens > p.llmTokens) {
    cost += ((usage.llmTokens - p.llmTokens) / 1000) * p.pricePerExtraLLM1k;
  }

  return Math.round(cost * 100) / 100;
}
