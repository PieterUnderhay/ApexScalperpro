# ApexScalperpro

## ApexScalperPro Version 1.0

ApexScalperPro 1.0 is a modular, Strategy Tester-ready MT5 Expert Advisor foundation. It provides closed-bar decision confirmation, trend/volatility/volume/spread/session filters, confidence gating, optional equity-risk sizing, magic-number-scoped position and hedging controls, dashboard telemetry, and central parameter validation.

`InpEnableTrading` remains `false` by default. Version 1.0 is intended for controlled MT5 Strategy Tester optimisation before any execution policy is enabled.

### Optimisation workflow

Run single-variable and walk-forward tests with fixed data, modelling mode, date range, spread, and symbol settings. Compare profit factor, maximum drawdown, trade count, recovery factor, and consecutive losses. Optimise decision thresholds, session hours, and risk sizing only after establishing a stable baseline.

### Phase 2 controls

The Phase 2 branch adds two independently configurable entry-quality controls: closed-candle body confirmation (`InpUseCandleConfirmation`, `InpMinimumCandleBodyATR`) and qualified-signal cooldown (`InpUseDecisionCooldown`, `InpDecisionCooldownSeconds`). Test each against the same baseline before combining them.

### Strategy Tester execution

To permit orders in MT5 Strategy Tester, set both `InpEnableTrading=true` and `InpEnableStrategyTesterTrading=true`. The Trade Engine additionally checks `MQL_TESTER`, so live execution remains blocked. New positions use configurable ATR stop-loss and take-profit distances; the Trade Manager can apply break-even and ATR trailing protection. Optimise these controls with fixed test data and realistic spread/commission assumptions.

### Phase 3 intelligent decision controls

Phase 3 adds configurable market-structure, support/resistance, and higher-timeframe confirmation gates. The Decision Engine requires the selected structure to agree with direction, rejects entries too close to opposing swing-derived levels, and can require M5 confirmation for an M1 strategy. The dashboard exposes structure and level-distance telemetry for diagnosis in Strategy Tester.

### Phase 4 telemetry

Phase 4 logs qualified trade candidates, including confidence and all active filter reasons, and records close reasons and net results from MT5 deal history. Dashboard statistics include signals, rejections, executed trades, wins/losses, average R, and consecutive win/loss streaks to support repeatable optimisation comparisons.

### Phase 5 research export

When `InpEnableResearchExport=true`, completed Strategy Tester trades are written to the configured CSV file under `MQL5/Files`. The test-end log includes core profitability, drawdown, win-rate, and R-multiple summary metrics. Keep the file name unique per optimisation run when retaining multiple result sets.
