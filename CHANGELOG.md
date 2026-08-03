# Changelog

## Version 0.7 - Money Management infrastructure

- Adds a reusable Money Management module with fixed-lot compatibility and optional equity-risk sizing.
- Dynamic sizing uses symbol tick value, tick size, equity, and a configurable reference stop distance.
- Adds parameter validation for risk percentage and reference-stop inputs; dynamic sizing remains disabled by default.

## Version 0.6 - Session-aware decision control

- Adds a reusable server-time session filter, including overnight-session support and input validation.
- Decision telemetry now rejects otherwise qualified setups outside the configured session and records the session reason.
- Default decision session is 07:00-20:00 server time; disable the filter for 24-hour optimisation runs.

## Version 0.5 - Decision Engine confirmation

- Evaluates directional, ADX, ATR, and volume signals from the last completed bar rather than the forming bar, reducing intrabar signal flicker in Strategy Tester.
- Adds configurable EMA-to-ATR and +DI/-DI separation filters to reject weak, compressed trend conditions.
- Adds a configurable decision-confidence threshold (default 70%) before BUY or SELL telemetry is produced.
- Keeps the existing market scanner, risk manager, dashboard, and execution-disabled behavior unchanged.

### Strategy Tester validation focus

Compare Version 0.4 and 0.5 on identical symbol, timeframe, spread, date range, and modelling settings. Evaluate trade count, profit factor, maximum drawdown, and consecutive losses. Optimise only the three new Decision Engine inputs within sensible ranges.
