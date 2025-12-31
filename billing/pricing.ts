export type Plan = 'FREE' | 'PRO' | 'ENTERPRISE';

export const PricingTable = {
  FREE: {
    sttMinutes: 30,
    ttsChars: 20000,
    llmTokens: 100000,
    pricePerExtraSTTMinute: 0.03,
    pricePerExtraTTS1k: 0.01,
    pricePerExtraLLM1k: 0.002,
  },
  PRO: {
    sttMinutes: 300,
    ttsChars: 300000,
    llmTokens: 2000000,
    pricePerExtraSTTMinute: 0.02,
    pricePerExtraTTS1k: 0.008,
    pricePerExtraLLM1k: 0.0015,
  },
  ENTERPRISE: {
    sttMinutes: Infinity,
    ttsChars: Infinity,
    llmTokens: Infinity,
    pricePerExtraSTTMinute: 0.015,
    pricePerExtraTTS1k: 0.006,
    pricePerExtraLLM1k: 0.001,
  },
};
