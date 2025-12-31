# Session Billing Integration

At session end:
1. Convert metrics → usage record
2. Store usage per user (D1 / KV / external DB)
3. Run calculateBill()
4. Enforce quota in next session

Recommended:
- Aggregate daily
- Bill monthly
