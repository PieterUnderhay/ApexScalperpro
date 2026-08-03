# Changelog

## Phase 5 - Strategy Tester Research Platform

- Adds optional CSV export to `MQL5/Files` for completed Strategy Tester trades, including entry/exit history, position sizing, SL/TP, duration, P/L, R multiple, and entry/exit reasons.
- Adds an end-of-test logged backtest summary covering net and gross P/L, profit factor, maximum drawdown, win rate, and average R.
- Preserves existing trade behavior; research export is disabled outside Strategy Tester.
- Adds configurable export enablement and filename inputs.
- Compiles with 0 errors and 0 warnings.

## Phase 4 - Optimisation and Trade Telemetry

- Logs each qualified trade candidate with direction, confidence, and active decision-filter reasons.
- Logs magic-number-isolated close transactions with net profit and broker deal reason.
- Adds performance counters for signals, rejected signals, executed trades, wins, losses, average R multiple, and maximum consecutive win/loss streaks.
- Tracks entry risk by position ID so closed-trade R multiples use the planned cash risk.
- Dashboard summary now exposes the new counters for Strategy Tester analysis.
- Compiles with 0 errors and 0 warnings.

## Phase 3 - Intelligent Decision Engine

- Adds Market Structure analysis for higher highs/lows, lower highs/lows, break of structure, and change of character states.
- Adds automatic swing-derived support/resistance levels and configurable rejection of entries too near the opposing level.
- Adds configurable higher-timeframe EMA, ADX, and DI confirmation.
- Integrates structure, support/resistance, and multi-timeframe checks into the existing decision gate without changing execution architecture.
- Dashboard now displays session, market structure, and support/resistance distance diagnostics.
- Adds validation for all new structure, support/resistance, timeframe, and trend-score controls.
- Compiles with 0 errors and 0 warnings.

## Phase 2 - Strategy Tester execution and trade management

- Adds the first executable entry path, permitted only when both `InpEnableTrading` and `InpEnableStrategyTesterTrading` are true and the EA is running in MT5 Strategy Tester. Live execution remains blocked.
- Adds ATR-derived initial stop loss and take profit with configurable multipliers and broker stop-level protection.
- Uses actual stop distance for optional equity-risk lot sizing; fixed lots remain supported.
- Adds a Trade Manager module for magic-number-isolated break-even and ATR trailing-stop management.
- Prevents duplicate managed positions in the same direction and retains the existing hedging and position-limit controls.
- Compiles with 0 errors and 0 warnings.

## Phase 2 - Signal quality controls

- Adds optional closed-candle direction/body confirmation, measured as a configurable fraction of ATR, to reduce weak and doji-like entries.
- Adds a per-symbol qualified-signal cooldown to reduce clustered signals; both controls are enabled by default and can be disabled or optimised in Strategy Tester.
- Compiles cleanly with 0 errors and 0 warnings.

## Version 1.0 - Strategy Tester-ready foundation

- Adds a central Configuration module with validation for market, decision, session, risk, money-management, and position inputs.
- Promotes the EA to Version 1.0 with a clean MetaEditor build: 0 errors and 0 warnings.
- Preserves the execution safety default: `InpEnableTrading=false`.
- The Decision, Session, Money Management, Position, Hedging, Statistics, Dashboard, Risk, Indicator, Market Scanner, Logging, and Configuration modules are ready for measured MT5 Strategy Tester optimisation.

## Version 0.9 - Decision statistics

- Adds a reusable Statistics module that records BUY, SELL, and NO TRADE decision outcomes.
- Dashboard now displays per-run decision telemetry to support Strategy Tester parameter comparison.
- Statistics remains independent of execution and does not alter trading behaviour.

## Version 0.8 - Position and Hedging infrastructure

- Adds read-only Position Manager and Hedging Manager modules scoped by symbol and EA magic number.
- Adds future position-limit and opposing-exposure guards without placing, modifying, or closing trades.
- Adds optimisable maximum-position and hedging-permission inputs, defaulting to one position and no hedging.

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
