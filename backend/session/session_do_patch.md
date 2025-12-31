# Patch SessionDO to emit metrics

At session end (disconnect or timeout):

import { flushMetrics } from './session_do_metrics';

await flushMetrics(env, sessionId, this.metrics, userId);
