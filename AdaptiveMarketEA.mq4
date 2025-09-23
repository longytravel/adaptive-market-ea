#property strict

#define MAX_SYMBOLS 16
#define MAX_NEWS_EVENTS 128
#include <AdaptiveDashboard.mqh>

struct SymbolState
{
   string  name;
   double  weightTrend;
   double  weightMicro;
   double  weightReversion;
   double  weightBreakout;
   double  bias;
   double  riskMultiplier;
   double  llmBias;
   string  regime;
   double  lastScore;
   double  lastTrendScore;
   double  lastMicroScore;
   double  lastReversionScore;
   double  lastBreakoutScore;
   datetime lastSignalTime;
   datetime lastBarTime;
   bool    tradingHalted;
};

struct NewsEvent
{
   string  symbol;
   datetime timestamp;
   int     impact;
   int     blockMinutes;
   string  description;
};

input string  InpSymbols                = "EURUSD,GBPUSD,USDJPY,XAUUSD";
input double  InpRiskPerTrade           = 1.0;
input double  InpDailyLossLimit         = 6.0;
input double  InpMaxSpreadPoints        = 25.0;
input double  InpAtrStopMultiplier      = 2.2;
input double  InpAtrTrailMultiplier     = 1.6;
input double  InpMinStopPoints          = 75.0;
input double  InpTPtoSL                 = 1.8;
input double  InpEntryThresholdLong     = 0.35;
input double  InpEntryThresholdShort    = -0.35;
input double  InpNeutralExitThreshold   = 0.08;
input int     InpSlippage               = 3;
input double  InpBaseLot                = 0.10;
input int     InpMagicNumber            = 460321;
input string  InpModelFile              = "models\\regime_signals.json";
input int     InpModelReloadMinutes     = 15;
input string  InpNewsFile               = "models\\news_schedule.csv";
input bool    InpEnableNewsFilter       = true;
input int     InpNewsReloadMinutes      = 30;
input bool    InpAllowOppositeFlip      = true;
input int     InpTimeExitMinutes        = 720;
input double  InpMaxRiskMultiplier      = 3.0;

SymbolState gStates[MAX_SYMBOLS];
AdaptiveDashboard gDashboard;
int gSymbolCount = 0;

double gDefaultWeightTrend     = 0.35;
double gDefaultWeightMicro     = 0.25;
double gDefaultWeightReversion = 0.20;
double gDefaultWeightBreakout  = 0.20;
double gDefaultBias            = 0.0;
double gDefaultRiskMultiplier  = 1.0;
string gDefaultRegime          = "balanced";

double gGlobalSentiment        = 0.0;
double gGlobalRiskMultiplier   = 1.0;
double gGlobalRiskCap          = 1.0;
double gNewsBlockMinutes       = 30.0;
string gModelUpdated        = "";

NewsEvent gNewsEvents[MAX_NEWS_EVENTS];
int gNewsEventCount = 0;

datetime gLastModelLoad = 0;
datetime gLastNewsLoad  = 0;
datetime gLastReportGenerated = 0;

datetime gDailyAnchorTime = 0;
double   gDailyAnchorEquity = 0.0;
bool     gTradingHaltedByLoss = false;

string   gLastModelError = "";

// Performance Logging System
struct TradeLogEntry
{
   int      ticket;
   string   symbol;
   datetime openTime;
   datetime closeTime;
   int      direction;         // 1=long, -1=short
   double   openPrice;
   double   closePrice;
   double   lots;
   double   stopLoss;
   double   takeProfit;
   double   profit;
   double   swap;
   double   commission;

   // Strategy scores at entry
   double   entryScore;
   double   entryTrendScore;
   double   entryMicroScore;
   double   entryReversionScore;
   double   entryBreakoutScore;
   string   dominantStrategy;
   string   reasoning;

   // Strategy scores at exit (if available)
   double   exitScore;
   double   exitTrendScore;
   double   exitMicroScore;
   double   exitReversionScore;
   double   exitBreakoutScore;

   // Market conditions
   double   entrySpread;
   double   entryATR;
   bool     newsBlocked;
   string   regime;

   // Performance metrics
   double   maxFavorableExcursion;
   double   maxAdverseExcursion;
   int      durationMinutes;
   string   exitReason;

   // Risk metrics
   double   riskAmount;
   double   riskMultiplier;
   double   accountBalance;
};

#define MAX_TRADE_LOG 1000
TradeLogEntry gTradeLog[MAX_TRADE_LOG];
int gTradeLogCount = 0;

// Performance tracking
struct StrategyStats
{
   string   name;
   int      totalTrades;
   int      winTrades;
   double   totalProfit;
   double   avgProfit;
   double   maxWin;
   double   maxLoss;
   double   avgDuration;
};

StrategyStats gStrategyStats[4]; // trend, micro, reversion, breakout

string TrimString(string value)
{
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
}

double ClampDouble(const double value, const double minValue, const double maxValue)
{
   if(value < minValue)
      return minValue;
   if(value > maxValue)
      return maxValue;
   return value;
}

double SignDouble(const double value)
{
   if(value > 0.0)
      return 1.0;
   if(value < 0.0)
      return -1.0;
   return 0.0;
}

datetime DateFloor(const datetime value)
{
   if(value <= 0)
      return 0;
   return value - (value % 86400);
}

string ToUpperString(string value)
{
   StringToUpper(value);
   return value;
}

string GenerateSignal(const double score)
{
   if(score >= InpEntryThresholdLong)
      return "BUY";
   else if(score <= InpEntryThresholdShort)
      return "SELL";
   else if(MathAbs(score) <= InpNeutralExitThreshold)
      return "EXIT";
   else
      return "HOLD";
}

string GenerateReasoning(const SymbolState &state)
{
   string reasoning = "";
   string dominant = "";
   double maxContribution = 0.0;

   // Find the dominant strategy
   double trendContrib = MathAbs(state.lastTrendScore * state.weightTrend);
   double microContrib = MathAbs(state.lastMicroScore * state.weightMicro);
   double reversionContrib = MathAbs(state.lastReversionScore * state.weightReversion);
   double breakoutContrib = MathAbs(state.lastBreakoutScore * state.weightBreakout);

   if(trendContrib > maxContribution)
   {
      maxContribution = trendContrib;
      if(state.lastTrendScore > 0.3)
         dominant = "Strong Uptrend";
      else if(state.lastTrendScore < -0.3)
         dominant = "Strong Downtrend";
      else
         dominant = "Weak Trend";
   }

   if(microContrib > maxContribution)
   {
      maxContribution = microContrib;
      if(state.lastMicroScore > 0.3)
         dominant = "Volume Surge + Momentum";
      else if(state.lastMicroScore < -0.3)
         dominant = "Selling Pressure";
      else
         dominant = "Mixed Volume Signals";
   }

   if(reversionContrib > maxContribution)
   {
      maxContribution = reversionContrib;
      if(state.lastReversionScore > 0.3)
         dominant = "Mean Reversion from Oversold";
      else if(state.lastReversionScore < -0.3)
         dominant = "Mean Reversion from Overbought";
      else
         dominant = "Price Near Average";
   }

   if(breakoutContrib > maxContribution)
   {
      maxContribution = breakoutContrib;
      if(state.lastBreakoutScore > 0.3)
         dominant = "Breakout Above Range";
      else if(state.lastBreakoutScore < -0.3)
         dominant = "Breakdown Below Range";
      else
         dominant = "Range-bound Price";
   }

   // Add secondary factors
   string secondary = "";
   if(state.bias != 0.0)
   {
      if(state.bias > 0.1)
         secondary += " + Bullish Bias";
      else if(state.bias < -0.1)
         secondary += " + Bearish Bias";
   }

   if(MathAbs(state.lastScore) < 0.1)
      reasoning = "Price Consolidating Near Average";
   else
      reasoning = dominant + secondary;

   return reasoning;
}

string GetDominantStrategy(const SymbolState &state)
{
   double maxContribution = 0.0;
   string dominant = "trend";

   double trendContrib = MathAbs(state.lastTrendScore * state.weightTrend);
   double microContrib = MathAbs(state.lastMicroScore * state.weightMicro);
   double reversionContrib = MathAbs(state.lastReversionScore * state.weightReversion);
   double breakoutContrib = MathAbs(state.lastBreakoutScore * state.weightBreakout);

   if(trendContrib > maxContribution)
   {
      maxContribution = trendContrib;
      dominant = "trend";
   }
   if(microContrib > maxContribution)
   {
      maxContribution = microContrib;
      dominant = "microstructure";
   }
   if(reversionContrib > maxContribution)
   {
      maxContribution = reversionContrib;
      dominant = "reversion";
   }
   if(breakoutContrib > maxContribution)
   {
      maxContribution = breakoutContrib;
      dominant = "breakout";
   }

   return dominant;
}

void LogTradeEntry(const int ticket, const SymbolState &state, const int direction,
                   const double openPrice, const double lots, const double stopLoss,
                   const double takeProfit, const double entrySpread, const double entryATR)
{
   if(gTradeLogCount >= MAX_TRADE_LOG)
      return; // Log is full

   TradeLogEntry entry; // Local struct, no reference

   entry.ticket = ticket;
   entry.symbol = state.name;
   entry.openTime = TimeCurrent();
   entry.closeTime = 0;
   entry.direction = direction;
   entry.openPrice = openPrice;
   entry.closePrice = 0.0;
   entry.lots = lots;
   entry.stopLoss = stopLoss;
   entry.takeProfit = takeProfit;
   entry.profit = 0.0;
   entry.swap = 0.0;
   entry.commission = 0.0;

   // Strategy scores at entry
   entry.entryScore = state.lastScore;
   entry.entryTrendScore = state.lastTrendScore;
   entry.entryMicroScore = state.lastMicroScore;
   entry.entryReversionScore = state.lastReversionScore;
   entry.entryBreakoutScore = state.lastBreakoutScore;
   entry.dominantStrategy = GetDominantStrategy(state);
   entry.reasoning = GenerateReasoning(state);

   // Market conditions
   entry.entrySpread = entrySpread;
   entry.entryATR = entryATR;
   entry.newsBlocked = CheckNewsBlock(state.name, TimeCurrent());
   entry.regime = state.regime;

   // Risk metrics
   entry.riskMultiplier = state.riskMultiplier;
   entry.accountBalance = AccountBalance();
   entry.riskAmount = AccountEquity() * (InpRiskPerTrade / 100.0) * entry.riskMultiplier;

   // Performance metrics (will be updated during trade life)
   entry.maxFavorableExcursion = 0.0;
   entry.maxAdverseExcursion = 0.0;
   entry.durationMinutes = 0;
   entry.exitReason = "open";

   // Copy to array
   gTradeLog[gTradeLogCount] = entry;
   gTradeLogCount++;

   // Log to file immediately
   WriteTradeEntryLog(entry);
}

void WriteTradeEntryLog(const TradeLogEntry &entry)
{
   string filename = "trade_entries_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
   int handle = FileOpen(filename, FILE_WRITE|FILE_CSV, ",");

   if(handle == INVALID_HANDLE)
   {
      // Try to create header if file doesn't exist
      handle = FileOpen(filename, FILE_WRITE|FILE_CSV, ",");
      if(handle != INVALID_HANDLE)
      {
         FileWrite(handle, "Ticket,Symbol,OpenTime,Direction,OpenPrice,Lots,StopLoss,TakeProfit",
                          "EntryScore,TrendScore,MicroScore,ReversionScore,BreakoutScore",
                          "DominantStrategy,Reasoning,Spread,ATR,NewsBlocked,Regime",
                          "RiskAmount,RiskMultiplier,AccountBalance");
         FileClose(handle);
      }

      // Reopen in append mode
      handle = FileOpen(filename, FILE_WRITE|FILE_CSV, ",");
   }

   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END); // Go to end of file

      FileWrite(handle,
         entry.ticket, entry.symbol, TimeToString(entry.openTime, TIME_DATE|TIME_MINUTES),
         entry.direction, entry.openPrice, entry.lots, entry.stopLoss, entry.takeProfit,
         entry.entryScore, entry.entryTrendScore, entry.entryMicroScore,
         entry.entryReversionScore, entry.entryBreakoutScore,
         entry.dominantStrategy, entry.reasoning, entry.entrySpread, entry.entryATR,
         entry.newsBlocked, entry.regime, entry.riskAmount, entry.riskMultiplier,
         entry.accountBalance);

      FileClose(handle);
   }
}

void LogTradeExit(const int ticket, const string exitReason, const SymbolState &state)
{
   // Find the trade in our log
   int logIndex = -1;
   for(int i = 0; i < gTradeLogCount; i++)
   {
      if(gTradeLog[i].ticket == ticket)
      {
         logIndex = i;
         break;
      }
   }

   if(logIndex == -1)
      return; // Trade not found in log

   TradeLogEntry entry = gTradeLog[logIndex]; // Copy to local struct

   // Get current order details
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      // Order might be closed, try to get from history
      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
         return;
   }

   entry.closeTime = OrderCloseTime();
   entry.closePrice = OrderClosePrice();
   entry.profit = OrderProfit();
   entry.swap = OrderSwap();
   entry.commission = OrderCommission();
   entry.exitReason = exitReason;

   // Strategy scores at exit (current market state)
   entry.exitScore = state.lastScore;
   entry.exitTrendScore = state.lastTrendScore;
   entry.exitMicroScore = state.lastMicroScore;
   entry.exitReversionScore = state.lastReversionScore;
   entry.exitBreakoutScore = state.lastBreakoutScore;

   // Calculate duration
   entry.durationMinutes = (int)((entry.closeTime - entry.openTime) / 60);

   // Copy modified struct back to array
   gTradeLog[logIndex] = entry;

   // Write to exit log
   WriteTradeExitLog(entry);

   // Update strategy statistics
   UpdateStrategyStats(entry);
}

void WriteTradeExitLog(const TradeLogEntry &entry)
{
   string filename = "trade_exits_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
   int handle = FileOpen(filename, FILE_WRITE|FILE_CSV, ",");

   if(handle == INVALID_HANDLE)
   {
      // Try to create header if file doesn't exist
      handle = FileOpen(filename, FILE_WRITE|FILE_CSV, ",");
      if(handle != INVALID_HANDLE)
      {
         FileWrite(handle, "Ticket,Symbol,OpenTime,CloseTime,Direction,OpenPrice,ClosePrice",
                          "Lots,Profit,Swap,Commission,NetProfit,Duration",
                          "EntryScore,ExitScore,TrendEntry,TrendExit,MicroEntry,MicroExit",
                          "ReversionEntry,ReversionExit,BreakoutEntry,BreakoutExit",
                          "DominantStrategy,ExitReason,MaxFavorable,MaxAdverse,Spread,ATR",
                          "NewsBlocked,Regime,RiskAmount,AccountBalance");
         FileClose(handle);
      }

      // Reopen in append mode
      handle = FileOpen(filename, FILE_WRITE|FILE_CSV, ",");
   }

   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END);

      double netProfit = entry.profit + entry.swap + entry.commission;

      FileWrite(handle,
         entry.ticket, entry.symbol,
         TimeToString(entry.openTime, TIME_DATE|TIME_MINUTES),
         TimeToString(entry.closeTime, TIME_DATE|TIME_MINUTES),
         entry.direction, entry.openPrice, entry.closePrice, entry.lots,
         entry.profit, entry.swap, entry.commission, netProfit, entry.durationMinutes,
         entry.entryScore, entry.exitScore,
         entry.entryTrendScore, entry.exitTrendScore,
         entry.entryMicroScore, entry.exitMicroScore,
         entry.entryReversionScore, entry.exitReversionScore,
         entry.entryBreakoutScore, entry.exitBreakoutScore,
         entry.dominantStrategy, entry.exitReason,
         entry.maxFavorableExcursion, entry.maxAdverseExcursion,
         entry.entrySpread, entry.entryATR, entry.newsBlocked, entry.regime,
         entry.riskAmount, entry.accountBalance);

      FileClose(handle);
   }
}

void UpdateRunningTradeMetrics()
{
   // Update max favorable/adverse excursion for open trades
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != InpMagicNumber)
         continue;

      int ticket = OrderTicket();

      // Find in our log
      int logIndex = -1;
      for(int j = 0; j < gTradeLogCount; j++)
      {
         if(gTradeLog[j].ticket == ticket && gTradeLog[j].closeTime == 0)
         {
            logIndex = j;
            break;
         }
      }

      if(logIndex == -1)
         continue;

      TradeLogEntry entry = gTradeLog[logIndex]; // Copy to local struct
      double currentProfit = OrderProfit() + OrderSwap() + OrderCommission();

      // Update max favorable excursion
      if(currentProfit > entry.maxFavorableExcursion)
         entry.maxFavorableExcursion = currentProfit;

      // Update max adverse excursion (most negative value)
      if(currentProfit < entry.maxAdverseExcursion)
         entry.maxAdverseExcursion = currentProfit;

      // Copy modified struct back to array
      gTradeLog[logIndex] = entry;
   }
}

void InitializeStrategyStats()
{
   gStrategyStats[0].name = "trend";
   gStrategyStats[1].name = "microstructure";
   gStrategyStats[2].name = "reversion";
   gStrategyStats[3].name = "breakout";

   for(int i = 0; i < 4; i++)
   {
      gStrategyStats[i].totalTrades = 0;
      gStrategyStats[i].winTrades = 0;
      gStrategyStats[i].totalProfit = 0.0;
      gStrategyStats[i].avgProfit = 0.0;
      gStrategyStats[i].maxWin = 0.0;
      gStrategyStats[i].maxLoss = 0.0;
      gStrategyStats[i].avgDuration = 0.0;
   }
}

int GetStrategyIndex(const string strategyName)
{
   for(int i = 0; i < 4; i++)
   {
      if(gStrategyStats[i].name == strategyName)
         return i;
   }
   return 0; // Default to trend
}

void UpdateStrategyStats(const TradeLogEntry &entry)
{
   int index = GetStrategyIndex(entry.dominantStrategy);

   double netProfit = entry.profit + entry.swap + entry.commission;

   gStrategyStats[index].totalTrades++;
   gStrategyStats[index].totalProfit += netProfit;

   if(netProfit > 0)
      gStrategyStats[index].winTrades++;

   if(netProfit > gStrategyStats[index].maxWin)
      gStrategyStats[index].maxWin = netProfit;

   if(netProfit < gStrategyStats[index].maxLoss)
      gStrategyStats[index].maxLoss = netProfit;

   // Update averages
   gStrategyStats[index].avgProfit = gStrategyStats[index].totalProfit / gStrategyStats[index].totalTrades;

   // Average duration calculation (running average)
   if(gStrategyStats[index].totalTrades == 1)
      gStrategyStats[index].avgDuration = entry.durationMinutes;
   else
      gStrategyStats[index].avgDuration = ((gStrategyStats[index].avgDuration * (gStrategyStats[index].totalTrades - 1)) + entry.durationMinutes) / gStrategyStats[index].totalTrades;

   // Write strategy stats to file
   WriteStrategyStatsLog();
}

void WriteStrategyStatsLog()
{
   string filename = "strategy_stats_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
   int handle = FileOpen(filename, FILE_WRITE|FILE_CSV, ",");

   if(handle != INVALID_HANDLE)
   {
      // Write header
      FileWrite(handle, "Strategy,TotalTrades,WinTrades,WinRate,TotalProfit,AvgProfit,MaxWin,MaxLoss,AvgDurationMin");

      // Write stats for each strategy
      for(int i = 0; i < 4; i++)
      {
         StrategyStats stats = gStrategyStats[i];
         double winRate = (stats.totalTrades > 0) ? (stats.winTrades * 100.0 / stats.totalTrades) : 0.0;

         FileWrite(handle,
            stats.name,
            stats.totalTrades,
            stats.winTrades,
            winRate,
            stats.totalProfit,
            stats.avgProfit,
            stats.maxWin,
            stats.maxLoss,
            stats.avgDuration);
      }

      FileClose(handle);
   }
}

void GeneratePerformanceReport()
{
   string filename = "performance_report_" + TimeToString(TimeCurrent(), TIME_DATE) + ".txt";
   int handle = FileOpen(filename, FILE_WRITE|FILE_TXT);

   if(handle == INVALID_HANDLE)
      return;

   FileWrite(handle, "=== ADAPTIVE MARKET EA PERFORMANCE REPORT ===");
   FileWrite(handle, "Generated: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
   FileWrite(handle, "");

   // Overall statistics
   FileWrite(handle, "=== OVERALL PERFORMANCE ===");
   int totalTrades = 0;
   int totalWins = 0;
   double totalProfit = 0.0;
   double totalDuration = 0.0;

   for(int i = 0; i < 4; i++)
   {
      totalTrades += gStrategyStats[i].totalTrades;
      totalWins += gStrategyStats[i].winTrades;
      totalProfit += gStrategyStats[i].totalProfit;
      totalDuration += (gStrategyStats[i].avgDuration * gStrategyStats[i].totalTrades);
   }

   double overallWinRate = (totalTrades > 0) ? (totalWins * 100.0 / totalTrades) : 0.0;
   double avgProfitPerTrade = (totalTrades > 0) ? (totalProfit / totalTrades) : 0.0;
   double avgTradeDuration = (totalTrades > 0) ? (totalDuration / totalTrades) : 0.0;

   FileWrite(handle, "Total Trades: " + IntegerToString(totalTrades));
   FileWrite(handle, "Win Rate: " + DoubleToString(overallWinRate, 2) + "%");
   FileWrite(handle, "Total Profit: $" + DoubleToString(totalProfit, 2));
   FileWrite(handle, "Avg Profit Per Trade: $" + DoubleToString(avgProfitPerTrade, 2));
   FileWrite(handle, "Avg Trade Duration: " + DoubleToString(avgTradeDuration, 1) + " minutes");
   FileWrite(handle, "");

   // Strategy breakdown
   FileWrite(handle, "=== STRATEGY BREAKDOWN ===");
   for(int i = 0; i < 4; i++)
   {
      StrategyStats stats = gStrategyStats[i];
      double winRate = (stats.totalTrades > 0) ? (stats.winTrades * 100.0 / stats.totalTrades) : 0.0;

      FileWrite(handle, "");
      FileWrite(handle, "Strategy: " + stats.name);
      FileWrite(handle, "  Trades: " + IntegerToString(stats.totalTrades));
      FileWrite(handle, "  Win Rate: " + DoubleToString(winRate, 2) + "%");
      FileWrite(handle, "  Total Profit: $" + DoubleToString(stats.totalProfit, 2));
      FileWrite(handle, "  Avg Profit: $" + DoubleToString(stats.avgProfit, 2));
      FileWrite(handle, "  Best Win: $" + DoubleToString(stats.maxWin, 2));
      FileWrite(handle, "  Worst Loss: $" + DoubleToString(stats.maxLoss, 2));
      FileWrite(handle, "  Avg Duration: " + DoubleToString(stats.avgDuration, 1) + " minutes");
   }

   // Trade log summary
   FileWrite(handle, "");
   FileWrite(handle, "=== RECENT TRADE ANALYSIS ===");
   if(gTradeLogCount > 0)
   {
      int recentCount = MathMin(10, gTradeLogCount);
      FileWrite(handle, "Last " + IntegerToString(recentCount) + " trades:");

      for(int i = gTradeLogCount - recentCount; i < gTradeLogCount; i++)
      {
         TradeLogEntry entry = gTradeLog[i];
         if(entry.closeTime > 0) // Only closed trades
         {
            double netProfit = entry.profit + entry.swap + entry.commission;
            string result = (netProfit >= 0) ? "WIN" : "LOSS";

            FileWrite(handle, "  " + entry.symbol + " " + entry.dominantStrategy + " " +
                     result + " $" + DoubleToString(netProfit, 2) + " (" +
                     IntegerToString(entry.durationMinutes) + "min) - " + entry.exitReason);
         }
      }
   }

   // Recommendations
   FileWrite(handle, "");
   FileWrite(handle, "=== PERFORMANCE INSIGHTS ===");

   // Find best performing strategy
   int bestStrategy = 0;
   double bestPerformance = gStrategyStats[0].avgProfit;
   for(int i = 1; i < 4; i++)
   {
      if(gStrategyStats[i].totalTrades >= 3 && gStrategyStats[i].avgProfit > bestPerformance)
      {
         bestStrategy = i;
         bestPerformance = gStrategyStats[i].avgProfit;
      }
   }

   // Find worst performing strategy
   int worstStrategy = 0;
   double worstPerformance = gStrategyStats[0].avgProfit;
   for(int i = 1; i < 4; i++)
   {
      if(gStrategyStats[i].totalTrades >= 3 && gStrategyStats[i].avgProfit < worstPerformance)
      {
         worstStrategy = i;
         worstPerformance = gStrategyStats[i].avgProfit;
      }
   }

   FileWrite(handle, "Best performing strategy: " + gStrategyStats[bestStrategy].name +
            " (avg profit: $" + DoubleToString(bestPerformance, 2) + ")");
   FileWrite(handle, "Worst performing strategy: " + gStrategyStats[worstStrategy].name +
            " (avg profit: $" + DoubleToString(worstPerformance, 2) + ")");

   if(overallWinRate < 50.0)
      FileWrite(handle, "WARNING: Win rate below 50% - consider adjusting entry thresholds");

   if(avgTradeDuration > 300) // 5 hours
      FileWrite(handle, "NOTE: Average trade duration is long - consider tighter time exits");

   FileWrite(handle, "");
   FileWrite(handle, "=== DATA FILES ===");
   FileWrite(handle, "Detailed logs available in:");
   FileWrite(handle, "- trade_entries_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv");
   FileWrite(handle, "- trade_exits_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv");
   FileWrite(handle, "- strategy_stats_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv");

   FileClose(handle);
   Print("Performance report generated: ", filename);
}

void CreateDefaultModelFile()
{
   string defaultModel = "{";
   defaultModel += "\"updated\": \"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\",";
   defaultModel += "\"default\": {";
   defaultModel += "\"bias\": 0.0,";
   defaultModel += "\"risk_multiplier\": 1.0,";
   defaultModel += "\"regime\": \"balanced\",";
   defaultModel += "\"weights\": {";
   defaultModel += "\"trend\": 0.35,";
   defaultModel += "\"micro\": 0.25,";
   defaultModel += "\"reversion\": 0.20,";
   defaultModel += "\"breakout\": 0.20";
   defaultModel += "}},";
   defaultModel += "\"globals\": {";
   defaultModel += "\"sentiment_bias\": 0.0,";
   defaultModel += "\"risk_multiplier\": 1.0,";
   defaultModel += "\"risk_cap\": 1.0,";
   defaultModel += "\"news_block_minutes\": 30";
   defaultModel += "},";
   defaultModel += "\"symbols\": {}";
   defaultModel += "}";

   int handle = FileOpen(InpModelFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, defaultModel);
      FileClose(handle);
      Print("Created default model file: ", InpModelFile);
   }
}

bool JsonExtractObject(const string json, const string key, string &result)
{
   string needle = "\"" + key + "\"";
   int start = StringFind(json, needle);
   if(start < 0)
      return false;
   start = StringFind(json, "{", start);
   if(start < 0)
      return false;
   int depth = 0;
   int len = StringLen(json);
   for(int i=start; i<len; i++)
   {
      string ch = StringSubstr(json, i, 1);
      if(ch == "{")
         depth++;
      else if(ch == "}")
      {
         depth--;
         if(depth == 0)
         {
            result = StringSubstr(json, start, i - start + 1);
            return true;
         }
      }
   }
   return false;
}

double JsonGetNumber(const string json, const string key, const double fallback)
{
   string needle = "\"" + key + "\"";
   int idx = StringFind(json, needle);
   if(idx < 0)
      return fallback;
   idx = StringFind(json, ":", idx);
   if(idx < 0)
      return fallback;
   int start = idx + 1;
   int len = StringLen(json);
   while(start < len)
   {
      int c = StringGetChar(json, start);
      if(c == ' ' || c == '\n' || c == '\r' || c == '\t')
      {
         start++;
         continue;
      }
      break;
   }
   int end = start;
   while(end < len)
   {
      int c = StringGetChar(json, end);
      if(c == ',' || c == '}' || c == ']')
         break;
      end++;
   }
   string raw = StringSubstr(json, start, end - start);
   raw = TrimString(raw);
   if(StringLen(raw) == 0)
      return fallback;
   if(StringGetChar(raw, 0) == '"' && StringLen(raw) > 1)
      raw = StringSubstr(raw, 1, StringLen(raw) - 2);
   double value = StrToDouble(raw);
   if(!MathIsValidNumber(value))
      return fallback;
   return value;
}

string JsonGetString(const string json, const string key, const string fallback)
{
   string needle = "\"" + key + "\"";
   int idx = StringFind(json, needle);
   if(idx < 0)
      return fallback;
   idx = StringFind(json, ":", idx);
   if(idx < 0)
      return fallback;
   int start = idx + 1;
   int len = StringLen(json);
   while(start < len)
   {
      int c = StringGetChar(json, start);
      if(c == ' ' || c == '\n' || c == '\r' || c == '\t')
      {
         start++;
         continue;
      }
      break;
   }
   if(start >= len)
      return fallback;
   if(StringGetChar(json, start) != '"')
   {
      int end = start;
      while(end < len && StringGetChar(json, end) != ',' && StringGetChar(json, end) != '}')
         end++;
      string raw = StringSubstr(json, start, end - start);
      raw = TrimString(raw);
      return raw;
   }
   start++;
   int end = start;
   while(end < len)
   {
      int c = StringGetChar(json, end);
      if(c == '"')
         break;
      if(c == '\\' && end + 1 < len)
         end += 2;
      else
         end++;
   }
   string raw = StringSubstr(json, start, end - start);
   return raw;
}

void ResetSymbolState(SymbolState &state, const string symbol)
{
   state.name = symbol;
   state.weightTrend = gDefaultWeightTrend;
   state.weightMicro = gDefaultWeightMicro;
   state.weightReversion = gDefaultWeightReversion;
   state.weightBreakout = gDefaultWeightBreakout;
   state.bias = gDefaultBias;
   state.riskMultiplier = gDefaultRiskMultiplier;
   state.llmBias = 0.0;
   state.regime = gDefaultRegime;
   state.lastScore = 0.0;
   state.lastTrendScore = 0.0;
   state.lastMicroScore = 0.0;
   state.lastReversionScore = 0.0;
   state.lastBreakoutScore = 0.0;
   state.lastSignalTime = 0;
   state.lastBarTime = 0;
   state.tradingHalted = false;
}

int GetSymbolIndex(const string symbol)
{
   for(int i=0; i<gSymbolCount; i++)
   {
      if(gStates[i].name == symbol)
         return i;
   }
   return -1;
}

void ConfigureSymbolUniverse()
{
   gSymbolCount = 0;
   string parts[];
   int count = StringSplit(InpSymbols, ',', parts);
   if(count <= 0)
      return;
   for(int i=0; i<count && gSymbolCount < MAX_SYMBOLS; i++)
   {
      string sym = TrimString(parts[i]);
      if(StringLen(sym) == 0)
         continue;
      StringToUpper(sym);
      SymbolSelect(sym, true);
      ResetSymbolState(gStates[gSymbolCount], sym);
      gSymbolCount++;
   }
}

void ParseModelJson(const string json)
{
   gDefaultWeightTrend     = 0.35;
   gDefaultWeightMicro     = 0.25;
   gDefaultWeightReversion = 0.20;
   gDefaultWeightBreakout  = 0.20;
   gDefaultBias            = 0.0;
   gDefaultRiskMultiplier  = 1.0;
   gDefaultRegime          = "balanced";
   gGlobalSentiment        = 0.0;
   gGlobalRiskMultiplier   = 1.0;
   gGlobalRiskCap          = 1.0;
   gNewsBlockMinutes       = 30.0;

   gModelUpdated        = JsonGetString(json, "updated", gModelUpdated);
   string defaultObj;
   if(JsonExtractObject(json, "default", defaultObj))
   {
      gDefaultBias = JsonGetNumber(defaultObj, "bias", gDefaultBias);
      gDefaultRiskMultiplier = JsonGetNumber(defaultObj, "risk_multiplier", gDefaultRiskMultiplier);
      gDefaultRegime = JsonGetString(defaultObj, "regime", gDefaultRegime);
      string weightsObj;
      if(JsonExtractObject(defaultObj, "weights", weightsObj))
      {
         gDefaultWeightTrend     = JsonGetNumber(weightsObj, "trend", gDefaultWeightTrend);
         gDefaultWeightMicro     = JsonGetNumber(weightsObj, "micro", gDefaultWeightMicro);
         gDefaultWeightReversion = JsonGetNumber(weightsObj, "reversion", gDefaultWeightReversion);
         gDefaultWeightBreakout  = JsonGetNumber(weightsObj, "breakout", gDefaultWeightBreakout);
      }
   }

   string globalsObj;
   if(JsonExtractObject(json, "globals", globalsObj))
   {
      gGlobalSentiment      = JsonGetNumber(globalsObj, "sentiment_bias", gGlobalSentiment);
      gGlobalRiskMultiplier = JsonGetNumber(globalsObj, "risk_multiplier", gGlobalRiskMultiplier);
      gGlobalRiskCap        = JsonGetNumber(globalsObj, "risk_cap", gGlobalRiskCap);
      gNewsBlockMinutes     = JsonGetNumber(globalsObj, "news_block_minutes", gNewsBlockMinutes);
   }

   for(int i=0; i<gSymbolCount; i++)
      ResetSymbolState(gStates[i], gStates[i].name);

   string symbolsObj;
   if(JsonExtractObject(json, "symbols", symbolsObj))
   {
      for(int i=0; i<gSymbolCount; i++)
      {
         string symObj;
         if(!JsonExtractObject(symbolsObj, gStates[i].name, symObj))
            continue;
         gStates[i].bias = JsonGetNumber(symObj, "bias", gDefaultBias);
         gStates[i].riskMultiplier = JsonGetNumber(symObj, "risk_multiplier", gDefaultRiskMultiplier);
         gStates[i].llmBias = JsonGetNumber(symObj, "llm_bias", 0.0);
         gStates[i].regime = JsonGetString(symObj, "regime", gDefaultRegime);
         string weightsObj;
         if(JsonExtractObject(symObj, "weights", weightsObj))
         {
            gStates[i].weightTrend     = JsonGetNumber(weightsObj, "trend", gDefaultWeightTrend);
            gStates[i].weightMicro     = JsonGetNumber(weightsObj, "micro", gDefaultWeightMicro);
            gStates[i].weightReversion = JsonGetNumber(weightsObj, "reversion", gDefaultWeightReversion);
            gStates[i].weightBreakout  = JsonGetNumber(weightsObj, "breakout", gDefaultWeightBreakout);
         }
      }
   }
}

bool LoadModelFile()
{
   if(StringLen(InpModelFile) == 0)
   {
      gLastModelError = "no model file specified";
      return false;
   }

   int handle = FileOpen(InpModelFile, FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      // Try to create a default model file if it doesn't exist
      CreateDefaultModelFile();
      handle = FileOpen(InpModelFile, FILE_READ|FILE_TXT|FILE_ANSI);
      if(handle == INVALID_HANDLE)
      {
         gLastModelError = "model file not found - check MQL4/Files/" + InpModelFile;
         return false;
      }
   }
   string content = "";
   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      content += line;
      if(!FileIsEnding(handle))
         content += "\n";
   }
   FileClose(handle);
   if(StringLen(content) == 0)
   {
     gLastModelError = "model file empty";
     return false;
   }
   ParseModelJson(content);
   gLastModelLoad = TimeCurrent();
   gLastModelError = "";
   return true;
}


datetime ParseTimestamp(string text)
{
   text = TrimString(text);
   if(StringLen(text) == 0)
      return 0;
   int zPos = StringFind(text, "Z");
   if(zPos >= 0)
      text = StringSubstr(text, 0, zPos);
   int plusPos = StringFind(text, "+");
   if(plusPos >= 0)
      text = StringSubstr(text, 0, plusPos);
   else
   {
      int tzMinusPos = StringFind(text, "-", 11);
      if(tzMinusPos > 10)
         text = StringSubstr(text, 0, tzMinusPos);
   }
   StringReplace(text, "T", " ");
   StringReplace(text, "/", ".");
   StringReplace(text, "-", ".");
   text = TrimString(text);
   return StringToTime(text);
}

bool LoadNewsFile()
{
   gNewsEventCount = 0;
   if(!InpEnableNewsFilter || StringLen(InpNewsFile) == 0)
      return false;
   int handle = FileOpen(InpNewsFile, FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;
   while(!FileIsEnding(handle) && gNewsEventCount < MAX_NEWS_EVENTS)
   {
      string line = FileReadString(handle);
      if(StringLen(line) == 0)
         continue;
      line = TrimString(line);
      if(StringLen(line) == 0)
         continue;
      if(StringGetChar(line, 0) == '#')
         continue;
      string parts[];
      int count = StringSplit(line, ',', parts);
      if(count < 3)
         continue;
      string tsStr = TrimString(parts[0]);
      string sym = TrimString(parts[1]);
      string impactStr = TrimString(parts[2]);
      string desc = "";
      if(count > 3)
         desc = TrimString(parts[3]);
      datetime ts = ParseTimestamp(tsStr);
      int impact = (int)StrToInteger(impactStr);
      int block = (int)gNewsBlockMinutes;
      if(impact >= 3)
         block = (int)MathRound(gNewsBlockMinutes * 1.5);
      else if(impact == 2)
         block = (int)MathRound(gNewsBlockMinutes);
      else
         block = (int)MathRound(gNewsBlockMinutes * 0.5);
      if(block < 10)
         block = 10;
      gNewsEvents[gNewsEventCount].symbol = ToUpperString(sym);
      gNewsEvents[gNewsEventCount].timestamp = ts;
      gNewsEvents[gNewsEventCount].impact = impact;
      gNewsEvents[gNewsEventCount].blockMinutes = block;
      gNewsEvents[gNewsEventCount].description = desc;
      gNewsEventCount++;
   }
   FileClose(handle);
   gLastNewsLoad = TimeCurrent();
   return (gNewsEventCount > 0);
}

bool CheckNewsBlock(const string symbol, const datetime now)
{
   if(!InpEnableNewsFilter || gNewsEventCount == 0)
      return false;
   string symUpper = ToUpperString(symbol);
   for(int i=0; i<gNewsEventCount; i++)
   {
      if(gNewsEvents[i].timestamp == 0)
         continue;
      int diff = (int)MathAbs((double)(now - gNewsEvents[i].timestamp));
      if(diff <= gNewsEvents[i].blockMinutes * 60)
      {
         string eventSymbol = gNewsEvents[i].symbol;
         if(eventSymbol == "ALL" || eventSymbol == "*" || eventSymbol == symUpper)
            return true;
         if(StringLen(eventSymbol) == 3 && StringSubstr(symUpper, 0, 3) == eventSymbol)
            return true;
      }
   }
   return false;
}

bool CheckSpread(const string symbol)
{
   double ask = MarketInfo(symbol, MODE_ASK);
   double bid = MarketInfo(symbol, MODE_BID);
   double point = MarketInfo(symbol, MODE_POINT);
   if(ask <= 0.0 || bid <= 0.0 || point <= 0.0)
      return false;
   double spread = (ask - bid) / point;
   if(spread > InpMaxSpreadPoints)
      return false;
   return true;
}

double ComputeTrendScore(const string symbol)
{
   if(iBars(symbol, PERIOD_H1) < 120 || iBars(symbol, PERIOD_H4) < 80)
      return 0.0;
   double point = MarketInfo(symbol, MODE_POINT);
   if(point <= 0.0)
      point = 0.0001;
   double emaFastH1 = iMA(symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaSlowH1 = iMA(symbol, PERIOD_H1, 55, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaFastPrev = iMA(symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE, 1);
   double slope = (emaFastH1 - emaFastPrev) / (point * 10.0);
   double diff = (emaFastH1 - emaSlowH1) / (point * 20.0);
   double emaFastH4 = iMA(symbol, PERIOD_H4, 34, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaSlowH4 = iMA(symbol, PERIOD_H4, 89, 0, MODE_EMA, PRICE_CLOSE, 0);
   double adx = iADX(symbol, PERIOD_H1, 14, PRICE_CLOSE, MODE_MAIN, 0);
   double adxNorm = ClampDouble((adx - 20.0) / 25.0, -1.0, 1.0);
   double direction = 0.0;
   if(emaFastH4 > emaSlowH4)
      direction = 1.0;
   else if(emaFastH4 < emaSlowH4)
      direction = -1.0;
   double score = 0.45 * ClampDouble(diff, -1.5, 1.5)
                + 0.35 * ClampDouble(slope, -1.2, 1.2)
                + 0.20 * adxNorm * direction;
   return ClampDouble(score, -1.0, 1.0);
}

double ComputeMicrostructureScore(const string symbol)
{
   if(iBars(symbol, PERIOD_M1) < 40)
      return 0.0;
   double point = MarketInfo(symbol, MODE_POINT);
   if(point <= 0.0)
      point = 0.0001;
   double volNow = iVolume(symbol, PERIOD_M1, 0);
   double volAvg = 0.0;
   for(int i=1; i<=20; i++)
      volAvg += iVolume(symbol, PERIOD_M1, i);
   volAvg /= 20.0;
   double volDelta = 0.0;
   if(volAvg > 0.0)
      volDelta = (volNow - volAvg) / volAvg;
   double closeNow = iClose(symbol, PERIOD_M1, 0);
   double closePrev = iClose(symbol, PERIOD_M1, 1);
   double momentum = (closeNow - closePrev) / (point * 6.0);
   double rangeHigh = iHigh(symbol, PERIOD_M1, 0);
   double rangeLow = iLow(symbol, PERIOD_M1, 0);
   double range = rangeHigh - rangeLow;
   double body = MathAbs(closeNow - iOpen(symbol, PERIOD_M1, 0));
   double imbalance = 0.0;
   if(range > 0.0)
      imbalance = (body / range) - 0.5;
   double score = 0.4 * ClampDouble(momentum, -1.5, 1.5)
                + 0.4 * ClampDouble(volDelta, -1.5, 1.5)
                + 0.2 * ClampDouble(imbalance * 2.0, -1.0, 1.0);
   return ClampDouble(score, -1.0, 1.0);
}

double ComputeReversionScore(const string symbol)
{
   if(iBars(symbol, PERIOD_M5) < 120)
      return 0.0;
   double atr = iATR(symbol, PERIOD_M5, 26, 0);
   if(!MathIsValidNumber(atr) || atr <= 0.0)
      return 0.0;
   double basis = iMA(symbol, PERIOD_M5, 55, 0, MODE_EMA, PRICE_TYPICAL, 0);
   double price = iClose(symbol, PERIOD_M5, 0);
   double dist = (basis - price) / atr;
   double sessionAnchor = iMA(symbol, PERIOD_M15, 96, 0, MODE_SMA, PRICE_TYPICAL, 0);
   double anchorDist = (sessionAnchor - price) / (atr * 1.5);
   double score = 0.6 * ClampDouble(dist, -2.5, 2.5) / 2.5
                + 0.4 * ClampDouble(anchorDist, -2.0, 2.0) / 2.0;
   return ClampDouble(score, -1.0, 1.0);
}

double ComputeBreakoutScore(const string symbol)
{
   if(iBars(symbol, PERIOD_M5) < 60)
      return 0.0;
   double atr = iATR(symbol, PERIOD_M5, 20, 0);
   if(!MathIsValidNumber(atr) || atr <= 0.0)
      return 0.0;
   double ema = iMA(symbol, PERIOD_M5, 34, 0, MODE_EMA, PRICE_TYPICAL, 0);
   int highsIndex = iHighest(symbol, PERIOD_M15, MODE_HIGH, 12, 0);
   int lowsIndex  = iLowest(symbol, PERIOD_M15, MODE_LOW, 12, 0);
   if(highsIndex < 0 || lowsIndex < 0)
      return 0.0;
   double rangeHigh = iHigh(symbol, PERIOD_M15, highsIndex);
   double rangeLow  = iLow(symbol, PERIOD_M15, lowsIndex);
   double range = rangeHigh - rangeLow;
   if(range <= 0.0 || !MathIsValidNumber(range))
      range = atr * 3.0;
   double closeNow = iClose(symbol, PERIOD_M5, 0);
   double closePrev = iClose(symbol, PERIOD_M5, 1);
   double impulse = (closeNow - closePrev) / MathMax(atr, 0.00001);
   double upper = ema + atr * 1.2;
   double lower = ema - atr * 1.2;
   double score = 0.0;
   if(closeNow > upper)
   {
      double overshoot = (closeNow - upper) / MathMax(atr * 0.6, 0.00001);
      score = ClampDouble(overshoot + impulse, -1.5, 1.5);
   }
   else if(closeNow < lower)
   {
      double overshoot = (lower - closeNow) / MathMax(atr * 0.6, 0.00001);
      score = -ClampDouble(overshoot - impulse, -1.5, 1.5);
   }
   else
   {
      score = ClampDouble(impulse * 0.6, -0.6, 0.6);
   }
   return ClampDouble(score, -1.0, 1.0);
}

double CalculatePositionSize(const string symbol, const double stopPoints, const SymbolState &state)
{
   double riskPerTrade = InpRiskPerTrade / 100.0;
   if(riskPerTrade <= 0.0)
      return 0.0;
   double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
   double minLot = MarketInfo(symbol, MODE_MINLOT);
   double maxLot = MarketInfo(symbol, MODE_MAXLOT);
   double lotStep = MarketInfo(symbol, MODE_LOTSTEP);
   if(lotStep <= 0.0)
      lotStep = 0.01;
   if(minLot <= 0.0)
      minLot = 0.01;
   if(maxLot <= 0.0)
      maxLot = 100.0;
   if(tickValue <= 0.0)
      tickValue = 1.0;
   double riskAmount = AccountEquity() * riskPerTrade;
   double multiplier = ClampDouble(gGlobalRiskMultiplier * state.riskMultiplier, 0.1, InpMaxRiskMultiplier);
   riskAmount *= multiplier;
   double stopValuePerLot = stopPoints * tickValue;
   if(stopValuePerLot <= 0.0)
      return InpBaseLot;
   double lots = riskAmount / stopValuePerLot;
   if(lots <= 0.0)
      lots = InpBaseLot;
   int lotDigits = 0;
   double tmp = lotStep;
   while(tmp < 1.0 && lotDigits < 5)
   {
      tmp *= 10.0;
      lotDigits++;
   }
   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;
   lots = NormalizeDouble(lots, lotDigits);
   return lots;
}

bool ClosePositions(const string symbol)
{
   return ClosePositionsWithReason(symbol, "signal_exit");
}

bool ClosePositionsWithReason(const string symbol, const string exitReason)
{
   bool result = true;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != InpMagicNumber)
         continue;
      if(OrderSymbol() != symbol)
         continue;

      int ticket = OrderTicket();
      int type = OrderType();

      // Get current symbol state for exit logging
      int symbolIndex = GetSymbolIndex(symbol);
      SymbolState state;
      if(symbolIndex >= 0)
         state = gStates[symbolIndex];

      bool closed = false;
      if(type == OP_BUY)
      {
         double price = MarketInfo(symbol, MODE_BID);
         closed = OrderClose(ticket, OrderLots(), price, InpSlippage, clrRed);
      }
      else if(type == OP_SELL)
      {
         double price = MarketInfo(symbol, MODE_ASK);
         closed = OrderClose(ticket, OrderLots(), price, InpSlippage, clrGreen);
      }

      if(closed && symbolIndex >= 0)
      {
         // Log the trade exit
         LogTradeExit(ticket, exitReason, state);
      }

      result = result && closed;
   }
   return result;
}

int GetPositionDirection(const string symbol)
{
   int direction = 0;
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != InpMagicNumber)
         continue;
      if(OrderSymbol() != symbol)
         continue;
      if(OrderType() == OP_BUY)
         direction++;
      else if(OrderType() == OP_SELL)
         direction--;
   }
   if(direction > 0)
      return 1;
   if(direction < 0)
      return -1;
   return 0;
}

bool OpenPosition(SymbolState &state, const int direction, const double stopPoints, const double takeProfitPoints, const double score)
{
   string symbol = state.name;
   RefreshRates();
   double ask = MarketInfo(symbol, MODE_ASK);
   double bid = MarketInfo(symbol, MODE_BID);
   double point = MarketInfo(symbol, MODE_POINT);
   if(point <= 0.0)
      point = 0.0001;
   if(ask <= 0.0 || bid <= 0.0)
      return false;
   double lots = CalculatePositionSize(symbol, stopPoints, state);
   if(lots <= 0.0)
      return false;
   int type = (direction > 0) ? OP_BUY : OP_SELL;
   double openPrice = (direction > 0) ? ask : bid;
   double stopPrice = (direction > 0) ? openPrice - stopPoints * point : openPrice + stopPoints * point;
   double takeProfitPrice = (direction > 0) ? openPrice + takeProfitPoints * point : openPrice - takeProfitPoints * point;
   color clr = (direction > 0) ? clrDeepSkyBlue : clrTomato;
   int ticket = OrderSend(symbol, type, lots, openPrice, InpSlippage, stopPrice, takeProfitPrice,
                          "AdaptiveMarketEA:" + DoubleToString(score, 2), InpMagicNumber, 0, clr);
   if(ticket < 0)
   {
      Print("OrderSend failed for ", symbol, " error ", GetLastError());
      return false;
   }

   // Calculate entry metrics for logging
   double entrySpread = (ask - bid) / point;
   double entryATR = iATR(symbol, PERIOD_M15, 14, 0) / point;

   // Log the trade entry with full context
   LogTradeEntry(ticket, state, direction, openPrice, lots, stopPrice, takeProfitPrice, entrySpread, entryATR);

   state.lastSignalTime = TimeCurrent();
   return true;
}

void ManagePositions()
{
   RefreshRates();
   datetime now = TimeCurrent();
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != InpMagicNumber)
         continue;
      string symbol = OrderSymbol();
      double point = MarketInfo(symbol, MODE_POINT);
      double atr = iATR(symbol, PERIOD_M5, 14, 0);
      if(point <= 0.0 || atr <= 0.0)
         continue;
      double atrPoints = atr / point;
      double trailGapPoints = atrPoints * InpAtrTrailMultiplier;
      if(trailGapPoints < InpMinStopPoints * 0.5)
         trailGapPoints = InpMinStopPoints * 0.5;
      int type = OrderType();
      if(type == OP_BUY)
      {
         double bid = MarketInfo(symbol, MODE_BID);
         double desired = bid - trailGapPoints * point;
         if(OrderStopLoss() < 0.00001 || desired > OrderStopLoss())
         {
            double tp = OrderTakeProfit();
            OrderModify(OrderTicket(), OrderOpenPrice(), desired, tp, 0, clrDodgerBlue);
         }
      }
      else if(type == OP_SELL)
      {
         double ask = MarketInfo(symbol, MODE_ASK);
         double desired = ask + trailGapPoints * point;
         if(OrderStopLoss() < 0.00001 || desired < OrderStopLoss())
         {
            double tp = OrderTakeProfit();
            OrderModify(OrderTicket(), OrderOpenPrice(), desired, tp, 0, clrTomato);
         }
      }
      if(InpTimeExitMinutes > 0)
      {
         int heldMinutes = (int)((now - OrderOpenTime()) / 60);
         if(heldMinutes >= InpTimeExitMinutes)
         {
            int ticket = OrderTicket();
            double price = (type == OP_BUY) ? MarketInfo(symbol, MODE_BID) : MarketInfo(symbol, MODE_ASK);
            bool closed = OrderClose(ticket, OrderLots(), price, InpSlippage, clrSilver);

            if(closed)
            {
               // Log time exit
               int symbolIndex = GetSymbolIndex(symbol);
               if(symbolIndex >= 0)
                  LogTradeExit(ticket, "time_exit", gStates[symbolIndex]);
            }
         }
      }
   }
}

void EvaluateSymbol(SymbolState &state, const datetime now)
{
   string symbol = state.name;
   if(state.tradingHalted)
      return;
   datetime barTime = iTime(symbol, PERIOD_M5, 0);
   if(barTime <= 0)
      return;
   if(barTime == state.lastBarTime)
      return;
   state.lastBarTime = barTime;

   if(CheckNewsBlock(symbol, now))
      return;
   if(!CheckSpread(symbol))
      return;

   double trendScore = ComputeTrendScore(symbol);
   double microScore = ComputeMicrostructureScore(symbol);
   double reversionScore = ComputeReversionScore(symbol);
   double breakoutScore = ComputeBreakoutScore(symbol);
   state.lastTrendScore = trendScore;
   state.lastMicroScore = microScore;
   state.lastReversionScore = reversionScore;
   state.lastBreakoutScore = breakoutScore;
   double weightSum = state.weightTrend + state.weightMicro + state.weightReversion + state.weightBreakout;
   if(weightSum <= 0.0001)
      weightSum = 1.0;
   double blended = (state.weightTrend * trendScore
                   + state.weightMicro * microScore
                   + state.weightReversion * reversionScore
                   + state.weightBreakout * breakoutScore) / weightSum;
   double aggregated = blended + state.bias + state.llmBias + gGlobalSentiment;
   aggregated = ClampDouble(aggregated, -1.5, 1.5);
   state.lastScore = aggregated;

   double atr = iATR(symbol, PERIOD_M15, 14, 0);
   if(!MathIsValidNumber(atr) || atr <= 0.0)
      return;
   double point = MarketInfo(symbol, MODE_POINT);
   if(point <= 0.0)
      return;
   double atrPoints = atr / point;
   double stopPoints = MathMax(InpMinStopPoints, atrPoints * InpAtrStopMultiplier);
   double tpPoints = stopPoints * InpTPtoSL;
   int existingDir = GetPositionDirection(symbol);

   if(aggregated >= InpEntryThresholdLong)
   {
      if(existingDir <= 0)
      {
         if(existingDir < 0 && InpAllowOppositeFlip)
            ClosePositionsWithReason(symbol, "opposite_flip");
         OpenPosition(state, 1, stopPoints, tpPoints, aggregated);
      }
   }
   else if(aggregated <= InpEntryThresholdShort)
   {
      if(existingDir >= 0)
      {
         if(existingDir > 0 && InpAllowOppositeFlip)
            ClosePositionsWithReason(symbol, "opposite_flip");
         OpenPosition(state, -1, stopPoints, tpPoints, aggregated);
      }
   }
   else
   {
      if(existingDir != 0 && MathAbs(aggregated) <= InpNeutralExitThreshold)
         ClosePositionsWithReason(symbol, "neutral_exit");
   }
}

void RefreshDashboard(const datetime now)
{
   DashboardSnapshot snap;
   snap.now = now;
   snap.balance = AccountBalance();
   snap.equity = AccountEquity();
   // Calculate daily P&L more accurately
   double currentBalance = AccountBalance();
   double openPnL = 0.0;

   // Add up all open position P&L for this EA
   for(int j=0; j<OrdersTotal(); j++)
   {
      if(OrderSelect(j, SELECT_BY_POS, MODE_TRADES) && OrderMagicNumber() == InpMagicNumber)
      {
         openPnL += OrderProfit() + OrderSwap() + OrderCommission();
      }
   }

   snap.dailyPnL = (currentBalance + openPnL) - gDailyAnchorEquity;
   snap.dailyPnLPercent = 0.0;
   if(gDailyAnchorEquity > 0.0)
      snap.dailyPnLPercent = 100.0 * snap.dailyPnL / gDailyAnchorEquity;
   snap.tradingHalted = gTradingHaltedByLoss;
   snap.globalSentiment = gGlobalSentiment;
   snap.globalRiskMultiplier = gGlobalRiskMultiplier;
   snap.globalRiskCap = gGlobalRiskCap;
   snap.modelUpdated = (StringLen(gModelUpdated) > 0) ? gModelUpdated : "n/a";
   snap.lastModelLoad = gLastModelLoad;
   snap.modelError = gLastModelError;
   snap.lossLimitInfo = StringFormat("Loss limit %.1f%%", InpDailyLossLimit);
   if(gDailyAnchorEquity > 0.0)
   {
      double threshold = gDailyAnchorEquity * (1.0 - InpDailyLossLimit / 100.0);
      double buffer = AccountEquity() - threshold;
      snap.lossLimitInfo += StringFormat("  buffer %.2f", buffer);
   }
   int count = gSymbolCount;
   if(count > DASHBOARD_MAX_SYMBOLS)
      count = DASHBOARD_MAX_SYMBOLS;
   snap.symbolCount = count;
   RefreshRates();
   for(int i=0; i<count; i++)
   {
      SymbolState state = gStates[i];
      snap.symbols[i].name = state.name;
      snap.symbols[i].regime = state.regime;
      snap.symbols[i].score = state.lastScore;
      snap.symbols[i].trendScore = state.lastTrendScore;
      snap.symbols[i].microScore = state.lastMicroScore;
      snap.symbols[i].reversionScore = state.lastReversionScore;
      snap.symbols[i].breakoutScore = state.lastBreakoutScore;
      snap.symbols[i].bias = state.bias;
      snap.symbols[i].llmBias = state.llmBias;
      snap.symbols[i].weightTrend = state.weightTrend;
      snap.symbols[i].weightMicro = state.weightMicro;
      snap.symbols[i].weightReversion = state.weightReversion;
      snap.symbols[i].weightBreakout = state.weightBreakout;
      double lots = 0.0;
      double profit = 0.0;
      int direction = 0;
      int totalOrders = OrdersTotal();
      for(int j=0; j<totalOrders; j++)
      {
         if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES))
            continue;
         if(OrderMagicNumber() != InpMagicNumber)
            continue;
         if(OrderSymbol() != state.name)
            continue;
         if(OrderType() == OP_BUY)
            direction++;
         else if(OrderType() == OP_SELL)
            direction--;
         lots += OrderLots();
         profit += OrderProfit() + OrderSwap() + OrderCommission();
      }
      if(direction > 0)
         snap.symbols[i].direction = 1;
      else if(direction < 0)
         snap.symbols[i].direction = -1;
      else
         snap.symbols[i].direction = 0;
      snap.symbols[i].lots = lots;
      snap.symbols[i].openProfit = profit;
      double ask = MarketInfo(state.name, MODE_ASK);
      double bid = MarketInfo(state.name, MODE_BID);
      double point = MarketInfo(state.name, MODE_POINT);
      double spread = 0.0;
      if(point > 0.0 && ask > 0.0 && bid > 0.0)
         spread = (ask - bid) / point;
      snap.symbols[i].spreadPoints = spread;
      snap.symbols[i].spreadBlocked = (spread > InpMaxSpreadPoints);
      snap.symbols[i].newsBlocked = CheckNewsBlock(state.name, now);
      snap.symbols[i].signal = GenerateSignal(state.lastScore);
      snap.symbols[i].reasoning = GenerateReasoning(state);
   }
   gDashboard.Update(snap);
}

void EvaluateSymbols(const datetime now)
{
   for(int i=0; i<gSymbolCount; i++)
      EvaluateSymbol(gStates[i], now);
}

void UpdateDailyAnchors(const datetime now)
{
   // Get midnight of current day (00:01 AM)
   datetime dayStart = DateFloor(now);

   if(gDailyAnchorTime == 0 || gDailyAnchorTime != dayStart)
   {
      gDailyAnchorTime = dayStart;
      // For first initialization, use current balance
      // For daily reset, this will be the balance at market open
      gDailyAnchorEquity = AccountBalance();
      gTradingHaltedByLoss = false;
      Print("Daily anchor reset - Day: ", TimeToString(dayStart, TIME_DATE), " Anchor balance: ", gDailyAnchorEquity);
   }
}

bool CheckDailyLossCut()
{
   if(InpDailyLossLimit <= 0.0)
      return false;
   if(gDailyAnchorEquity <= 0.0)
      gDailyAnchorEquity = AccountEquity();
   double threshold = gDailyAnchorEquity * (1.0 - InpDailyLossLimit / 100.0);
   if(AccountEquity() <= threshold)
   {
      if(!gTradingHaltedByLoss)
         Print("Daily loss limit reached. Halting new trades.");
      gTradingHaltedByLoss = true;
      return true;
   }
   return gTradingHaltedByLoss;
}

void CoreUpdate()
{
   datetime now = TimeCurrent();
   UpdateDailyAnchors(now);
   if(InpModelReloadMinutes > 0 && now - gLastModelLoad >= InpModelReloadMinutes * 60)
      LoadModelFile();
   if(InpEnableNewsFilter && InpNewsReloadMinutes > 0 && now - gLastNewsLoad >= InpNewsReloadMinutes * 60)
      LoadNewsFile();

   // Generate daily performance report
   datetime currentDay = DateFloor(now);
   int totalTrades = 0;
   for(int i = 0; i < 4; i++)
      totalTrades += gStrategyStats[i].totalTrades;

   if(gLastReportGenerated != currentDay && totalTrades > 0)
   {
      GeneratePerformanceReport();
      gLastReportGenerated = currentDay;
   }

   ManagePositions();
   UpdateRunningTradeMetrics(); // Update max favorable/adverse excursion

   if(CheckDailyLossCut())
   {
      RefreshDashboard(now);
      return;
   }
   EvaluateSymbols(now);
   RefreshDashboard(now);
}

int OnInit()
{
   ConfigureSymbolUniverse();
   LoadModelFile();
   if(InpEnableNewsFilter)
      LoadNewsFile();
   gDailyAnchorTime = DateFloor(TimeCurrent());
   gDailyAnchorEquity = AccountEquity();
   gTradingHaltedByLoss = false;

   // Initialize performance tracking
   InitializeStrategyStats();
   gTradeLogCount = 0;

   EventSetTimer(15);
   gDashboard.Init(0);
   RefreshDashboard(TimeCurrent());
   Print("AdaptiveMarketEA initialized with ", gSymbolCount, " symbols and performance logging enabled.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   gDashboard.Deinit();
}

void OnTick()
{
   CoreUpdate();
}

void OnTimer()
{
   CoreUpdate();
}









