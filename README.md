# ApexScalperpro

## ApexScalperPro Version 1.0

ApexScalperPro 1.0 is a modular, Strategy Tester-ready MT5 Expert Advisor foundation. It provides closed-bar decision confirmation, trend/volatility/volume/spread/session filters, confidence gating, optional equity-risk sizing, magic-number-scoped position and hedging controls, dashboard telemetry, and central parameter validation.

`InpEnableTrading` remains `false` by default. Version 1.0 is intended for controlled MT5 Strategy Tester optimisation before any execution policy is enabled.

### Optimisation workflow

Run single-variable and walk-forward tests with fixed data, modelling mode, date range, spread, and symbol settings. Compare profit factor, maximum drawdown, trade count, recovery factor, and consecutive losses. Optimise decision thresholds, session hours, and risk sizing only after establishing a stable baseline.

### Phase 2 controls

The Phase 2 branch adds two independently configurable entry-quality controls: closed-candle body confirmation (`InpUseCandleConfirmation`, `InpMinimumCandleBodyATR`) and qualified-signal cooldown (`InpUseDecisionCooldown`, `InpDecisionCooldownSeconds`). Test each against the same baseline before combining them.
