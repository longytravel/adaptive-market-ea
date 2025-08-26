# Adaptive Market EA - Multi-Strategy Forex Trading System

## Current Version: 3.1 (2025-08-26)
- ✅ Enhanced spacing in pair grid (4 columns)
- ✅ Chart open buttons for each pair
- ✅ Fixed market state display (BULL/BEAR)
- ✅ Better spread display (shows actual values)
- ✅ 26 pairs monitoring active
- ✅ 3-Strategy system working

## Features
- **Multi-pair monitoring** (26 pairs)
- **3 Strategy System** (Trend, Range, Breakout)
- **Adaptive market state detection**
- **One-click chart opening** with suggested indicators
- **Advanced risk management** (1% per trade, 3% daily max)
- **Real-time performance tracking**

## Quick Start
1. Copy mql4/AdaptiveMarket_Main.mq4 to MT4 MQL4/Experts folder
2. Compile in MetaEditor (F7)
3. Attach to any chart
4. Enable Auto Trading
5. Click [C] buttons to open individual pair charts

## Strategy States
- **BULL** - Uptrend detected (Trend strategy)
- **BEAR** - Downtrend detected (Trend strategy)
- **RANGE** - Sideways market (Range strategy)
- **BREAK** - Breakout detected (Breakout strategy)
- **WAIT** - No clear signal

## Known Issues
- Some pairs show high spread during off-hours
- Unicode arrows don't display (using BULL/BEAR instead)
- Manual indicator adding required on opened charts
