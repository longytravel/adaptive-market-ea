# Adaptive Market EA - Multi-Strategy Forex Trading System

## Overview
Advanced MetaTrader 4 Expert Advisor implementing multiple strategies across 26 currency pairs with adaptive market state detection.

## Features
- ✅ Multi-pair monitoring (26 pairs)
- ✅ 3 Strategy System (Trend, Range, Breakout)
- ✅ Adaptive market state detection
- ✅ Advanced risk management
- ✅ Beautiful dashboard interface
- ✅ Real-time performance tracking

## Current Version: 3.0
- Status: **3-Strategy System Active**
- Released: 2025-08-26
- Account:  initial
- Risk: 1% per trade
- Max Daily Loss: 3%

## Strategies
### 📈 Trend Strategy (Active when ADX > 25)
- Moving Average crossovers (20/50)
- ADX confirmation required
- Trades with strong directional movement

### 📊 Range Strategy (Active when ADX < 20)  
- RSI oversold/overbought (30/70)
- Bollinger Band reversals
- Mean reversion in consolidation

### 🚀 Breakout Strategy (Active when ATR > 1.5x average)
- Previous day high/low breaks
- Momentum confirmation
- Volatility expansion trades

## Quick Start
1. Copy mql4/AdaptiveMarket_Main.mq4 to MT4 MQL4/Experts folder
2. Compile in MetaEditor (F7)
3. Attach to any chart
4. Enable Auto Trading
5. Watch all 26 pairs from one chart!

## Dashboard Shows
- Account balance & equity
- Current P/L & daily P/L
- Strategy performance (trades per strategy)
- Win rate statistics
- All 26 pairs with color-coded market states

## Market State Colors
- 🟢 GREEN: Buy signal
- 🔴 RED: Sell signal
- 🟡 YELLOW: Ranging market
- 🟣 PURPLE: Breakout detected
- 🔵 AQUA: Trade active
- ⚫ GRAY: Waiting/Choppy

## Risk Management
- 1% risk per trade
- Maximum 5 concurrent trades
- 3% daily loss limit
- Automatic lot sizing
- Spread filter (max 2 pips)
