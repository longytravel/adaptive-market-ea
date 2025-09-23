# Adaptive Market EA

AdaptiveMarketEA is a multi-engine MetaTrader 4 expert advisor designed to ingest external model signals, blend advanced technical features, and execute tightly risk-managed intraday trades on highly liquid symbols.

## Key Features

- Multi-symbol orchestrator (default: EURUSD, GBPUSD, USDJPY, XAUUSD) operating from a single chart via timer events.
- On-chart adaptive dashboard (equity, drawdown buffer, model digest, per-symbol scores/weights).
- Four blended signal engines (trend, microstructure, mean-reversion, breakout) with per-symbol weights supplied by an external JSON model.
- Adaptive risk sizing using ATR-derived stop distances, volatility-aware trailing stops, position flips, and configurable daily drawdown kill-switch.
- News blackout support via CSV schedule with impact-based blocking windows.
- Pluggable offline intelligence pipeline (LLMs / ML) that can rewrite `models/regime_signals.json` without recompiling the EA.

## File Layout

```
AdaptiveMarketEA.mq4           # Expert advisor source
ui/AdaptiveDashboard.mqh        # Dashboard rendering helper
models/regime_signals.json     # Model weights, bias overrides, regimes
models/news_schedule.csv       # Upcoming news events (timestamp,symbol,impact,desc)
tools/regime_model_template.py # Sample Python generator for regime_signals.json
```

## Deployment (MT4)

1. Copy `AdaptiveMarketEA.mq4` into `<MT4 data folder>/MQL4/Experts/` and compile inside MetaEditor.
2. Copy the `models` directory into `<MT4 data folder>/MQL4/Files/` so the EA can read the JSON/CSV (or adjust the `InpModelFile`/`InpNewsFile` inputs to an absolute path you control).
3. Attach the EA to a single M5 chart of any supported symbol (spread filter ensures safe execution). Leave “Allow live trading” enabled.
4. Verify `Experts` tab logs show “AdaptiveMarketEA initialized…” without file errors.

## External Model Workflow

1. Use `tools/regime_model_template.py` (or your own pipeline) to regenerate `models/regime_signals.json` after each analytics update.
2. The EA reloads the model automatically every `InpModelReloadMinutes` (default 15). Manual reload is as simple as toggling the EA or rewriting the file.
3. Optional: schedule Python/LLM scripts to refresh weights and sentiment bias regularly.

### JSON Schema Highlights

- `default`: fallback bias, risk multiplier, and weights applied before symbol overrides.
- `globals.sentiment_bias`: pushes overall long/short appetite across all symbols (e.g., from macro narrative).
- `symbols[SYMBOL].weights`: relative importance of each engine; they do not need to sum to 1 (EA normalises internally).
- `symbols[SYMBOL].llm_bias`: additive tweak injected from LLM sentiment service (positive favors longs, negative favors shorts).

### News Filter

- CSV columns: `timestamp (ISO8601)`, `symbol` (e.g., `USD`, `ALL`, `EURUSD`), `impact (1-3)`, `description`.
- Impact adjusts blackout length (low ≈ 0.5×, medium ≈ 1×, high ≈ 1.5× of `news_block_minutes`).
- The EA checks every timer tick and skips new positions inside the blackout window.

## Inputs Overview

- `InpRiskPerTrade`: percent of equity risked per trade before multipliers.
- `InpDailyLossLimit`: daily drawdown (percent) that halts new trades until the next trading day.
- `InpEntryThresholdLong/Short`: signal score thresholds that trigger new positions.
- `InpModelFile`, `InpNewsFile`: paths to the external model and news schedule.
- `InpModelReloadMinutes`, `InpNewsReloadMinutes`: auto-reload cadence.

## Validation Ideas

1. Strategy Tester (M5, M15) across multiple years with different symbols; monitor aggregated score via `Experts` log.
2. Monte Carlo of `regime_signals.json` tweaks to confirm robustness.
3. Forward-test on a demo account; inspect `MQL4/Logs` for file read errors and execution anomalies.
4. Extend the Python template to include your actual ML features, macro sentiment APIs, or reinforcement feedback loop.

## Next Steps

- Integrate your analytics stack to feed model values.
- Add portfolio-level constraints (e.g., correlation throttling) if you extend to more symbols.
- Instrument additional telemetry (file writes, dashboards) as you iterate.

_Disclaimer: No profitability is guaranteed. Thorough backtesting and forward validation are mandatory before risking live capital._

