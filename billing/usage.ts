export interface UsageRecord {
  userId: string;
  sttMs: number;
  ttsChars: number;
  llmTokens: number;
}

export function aggregateUsage(records: UsageRecord[]) {
  return records.reduce(
    (acc, r) => {
      acc.sttMs += r.sttMs;
      acc.ttsChars += r.ttsChars;
      acc.llmTokens += r.llmTokens;
      return acc;
    },
    { sttMs: 0, ttsChars: 0, llmTokens: 0 }
  );
}
