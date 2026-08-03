# Changelog

## Version 0.5 - Decision Engine confirmation

- Evaluates directional, ADX, ATR, and volume signals from the last completed bar rather than the forming bar, reducing intrabar signal flicker in Strategy Tester.
- Adds configurable EMA-to-ATR and +DI/-DI separation filters to reject weak, compressed trend conditions.
- Adds a configurable decision-confidence threshold (default 70%) before BUY or SELL telemetry is produced.
- Keeps the existing market scanner, risk manager, dashboard, and execution-disabled behavior unchanged.

### Strategy Tester validation focus

Compare Version 0.4 and 0.5 on identical symbol, timeframe, spread, date range, and modelling settings. Evaluate trade count, profit factor, maximum drawdown, and consecutive losses. Optimise only the three new Decision Engine inputs within sensible ranges.
