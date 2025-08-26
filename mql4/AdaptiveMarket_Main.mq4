//+------------------------------------------------------------------+
//|                                          AdaptiveMarket_Main.mq4 |
//|                                    Your Adaptive Market EA v3.1 |
//|                    Enhanced UI with Chart Buttons & Spacing     |
//+------------------------------------------------------------------+
#property copyright "Adaptive Market EA v3.1"
#property version   "3.10"
#property strict

// ===== INPUT PARAMETERS =====
input string  Sep1 = "=== RISK MANAGEMENT ===";
input double RiskPercentage = 1.0;        // Risk % per trade
input int    MaxConcurrentTrades = 5;     // Maximum open trades
input int    StopLoss = 50;               // Stop Loss in pips
input int    TakeProfit = 100;            // Take Profit in pips
input double MaxDailyLoss = 3.0;          // Max daily loss %
input string  Sep2 = "=== STRATEGY SETTINGS ===";
input bool   UseTrendStrategy = true;     // Use Trend Strategy
input bool   UseRangeStrategy = true;     // Use Range Strategy  
input bool   UseBreakoutStrategy = true;  // Use Breakout Strategy
input int    ADX_Period = 14;             // ADX Period for trend
input int    RSI_Period = 14;             // RSI Period for range
input double MinSpread = 2.0;             // Maximum spread allowed
input string  Sep3 = "=== DISPLAY SETTINGS ===";
input ENUM_TIMEFRAMES ChartTimeframe = PERIOD_H1; // Timeframe for opened charts
input bool   ShowIndicatorsOnChart = true; // Add indicators to opened charts

// ===== GLOBAL VARIABLES =====
string EA_NAME = "ADAPTIVE MARKET EA v3.1";
int    MagicNumber = 123456;

// All 26 Forex pairs
string TradePairs[] = {
   "EURUSD", "GBPUSD", "USDJPY", "USDCHF", "USDCAD", "AUDUSD", "NZDUSD",
   "EURJPY", "GBPJPY", "EURAUD", "EURCAD", "EURCHF", "EURGBP", "EURNZD",
   "GBPAUD", "GBPCAD", "GBPCHF", "GBPNZD", "AUDJPY", "CADJPY", "CHFJPY",
   "NZDJPY", "AUDCAD", "AUDCHF", "AUDNZD", "CADCHF"
};
int TotalPairs = 26;

// Market states
enum MARKET_STATE {
   STATE_TREND_UP,
   STATE_TREND_DOWN,
   STATE_RANGE,
   STATE_BREAKOUT,
   STATE_CHOPPY
};

// Strategy types
enum STRATEGY_TYPE {
   STRATEGY_NONE,
   STRATEGY_TREND,
   STRATEGY_RANGE,
   STRATEGY_BREAKOUT
};

// Arrays for pair management
MARKET_STATE PairState[];
STRATEGY_TYPE ActiveStrategy[];
double PairSpread[];
double PairStrength[];
int PairTrades[];
datetime LastSignalTime[];
double PairProfit[];
color PairColor[];
string PairStatus[];
long ChartIDs[];  // Store chart IDs for each pair

// Performance tracking
int TotalTrades = 0;
int WinTrades = 0;
int LossTrades = 0;
int TrendTrades = 0;
int RangeTrades = 0;
int BreakoutTrades = 0;
double DailyStartBalance;
datetime DailyStartTime;

// ===== INITIALIZATION =====
int OnInit()
{
   Print("═══════════════════════════════════════");
   Print(EA_NAME + " INITIALIZING");
   Print("Account Balance: $", AccountBalance());
   Print("Monitoring: ", TotalPairs, " pairs");
   Print("Strategies: Trend, Range, Breakout");
   Print("═══════════════════════════════════════");
   
   // Initialize arrays
   ArrayResize(PairState, TotalPairs);
   ArrayResize(ActiveStrategy, TotalPairs);
   ArrayResize(PairSpread, TotalPairs);
   ArrayResize(PairStrength, TotalPairs);
   ArrayResize(PairTrades, TotalPairs);
   ArrayResize(LastSignalTime, TotalPairs);
   ArrayResize(PairProfit, TotalPairs);
   ArrayResize(PairColor, TotalPairs);
   ArrayResize(PairStatus, TotalPairs);
   ArrayResize(ChartIDs, TotalPairs);
   
   // Initialize values
   for(int i = 0; i < TotalPairs; i++) {
      PairState[i] = STATE_CHOPPY;
      ActiveStrategy[i] = STRATEGY_NONE;
      PairColor[i] = clrGray;
      PairStatus[i] = "WAITING";
      LastSignalTime[i] = 0;
      ChartIDs[i] = 0;
   }
   
   // Set up display
   SetupChart();
   CreateAdvancedDashboard();
   
   // Initialize daily tracking
   DailyStartBalance = AccountBalance();
   DailyStartTime = iTime(Symbol(), PERIOD_D1, 0);
   
   return(INIT_SUCCEEDED);
}

// ===== DEINITIALIZATION =====
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0);
   Print("EA Stopped. Total: ", TotalTrades, " | Win: ", WinTrades, " | Loss: ", LossTrades);
}

// ===== MAIN TICK FUNCTION =====
void OnTick()
{
   // Check daily loss limit
   if(CheckDailyLossLimit()) return;
   
   // Update main dashboard
   UpdateMainDashboard();
   
   // Analyze each pair
   for(int i = 0; i < TotalPairs; i++) {
      AnalyzePair(i);
   }
   
   // Update strategy panel
   UpdateStrategyPanel();
   
   // Manage existing trades
   ManageOpenTrades();
}

// ===== CHART EVENT HANDLER =====
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // Handle button clicks
   if(id == CHARTEVENT_OBJECT_CLICK) {
      // Check if it's a chart button
      if(StringFind(sparam, "BTN_") == 0) {
         // Extract pair index from button name
         string indexStr = StringSubstr(sparam, 4);
         int pairIndex = StringToInteger(indexStr);
         
         if(pairIndex >= 0 && pairIndex < TotalPairs) {
            OpenPairChart(pairIndex);
         }
         
         // Reset button state
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
   }
}

// ===== OPEN CHART WITH INDICATORS (FIXED) =====
void OpenPairChart(int index)
{
   string symbol = TradePairs[index];
   
   // Open new chart if not already open
   long chartID = ChartOpen(symbol, ChartTimeframe);
   
   if(chartID > 0) {
      ChartIDs[index] = chartID;
      
      // Apply template settings
      ChartSetInteger(chartID, CHART_SHOW_GRID, false);
      ChartSetInteger(chartID, CHART_COLOR_BACKGROUND, clrBlack);
      ChartSetInteger(chartID, CHART_COLOR_FOREGROUND, clrWhite);
      ChartSetInteger(chartID, CHART_COLOR_CANDLE_BULL, clrLime);
      ChartSetInteger(chartID, CHART_COLOR_CANDLE_BEAR, clrRed);
      ChartSetInteger(chartID, CHART_SHOW_VOLUMES, false);
      
      // Get current state for info
      MARKET_STATE state = PairState[index];
      
      // Create info text on the new chart
      string infoText = "";
      infoText = "═══ " + symbol + " ═══\n";
      infoText += "Strategy: " + StrategyToString(ActiveStrategy[index]) + "\n";
      infoText += "Market State: " + MarketStateToString(state) + "\n";
      infoText += "══════════════\n";
      
      // Add indicator suggestions based on state
      switch(state) {
         case STATE_TREND_UP:
         case STATE_TREND_DOWN:
            infoText += "TREND MODE\n";
            infoText += "Suggested: MA(20,50) + ADX(14)\n";
            break;
            
         case STATE_RANGE:
            infoText += "RANGE MODE\n";
            infoText += "Suggested: RSI(14) + Bollinger(20)\n";
            break;
            
         case STATE_BREAKOUT:
            infoText += "BREAKOUT MODE\n";
            infoText += "Suggested: ATR(14) + Previous High/Low\n";
            break;
            
         default:
            infoText += "CHOPPY/WAITING\n";
            infoText += "Monitor for clear signals\n";
      }
      
      // Add the comment to the new chart
      ChartSetString(chartID, CHART_COMMENT, infoText);
      
      // Create a label on the new chart with info
      string labelName = "INFO_" + symbol;
      ObjectCreate(chartID, labelName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(chartID, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(chartID, labelName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(chartID, labelName, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(chartID, labelName, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(chartID, labelName, OBJPROP_FONTSIZE, 9);
      ObjectSetString(chartID, labelName, OBJPROP_FONT, "Arial Bold");
      ObjectSetString(chartID, labelName, OBJPROP_TEXT, 
                     "Add indicators manually: " + 
                     (state == STATE_RANGE ? "RSI+BB" : 
                      state == STATE_TREND_UP || state == STATE_TREND_DOWN ? "MA+ADX" : 
                      state == STATE_BREAKOUT ? "ATR" : "MA"));
      
      ChartRedraw(chartID);
      Print("Opened chart for ", symbol);
   }
}

// ===== PAIR ANALYSIS =====
void AnalyzePair(int index)
{
   string symbol = TradePairs[index];
   
   // Check if symbol exists
   if(MarketInfo(symbol, MODE_BID) == 0) {
      PairStatus[index] = "OFFLINE";
      PairColor[index] = clrDarkGray;
      return;
   }
   
   // Get spread
   double spread = MarketInfo(symbol, MODE_SPREAD) / 10.0;
   PairSpread[index] = spread;
   
   // Check if spread too high
   if(spread > MinSpread) {
      PairStatus[index] = "SP:" + DoubleToString(spread,1);  // <--- CHANGED: Shows actual spread value
      PairColor[index] = clrOrange;
      return;
   }
   
   // Count open trades
   PairTrades[index] = CountPairTrades(symbol);
   
   // Check if we can open new trades
   if(CountAllTrades() >= MaxConcurrentTrades) {
      PairStatus[index] = "MAX";
      PairColor[index] = clrYellow;
      return;
   }
   
   // Check cooldown (5 minutes between signals)
   if(TimeCurrent() - LastSignalTime[index] < 300) return;
   
   // Detect market state
   MARKET_STATE state = DetectMarketState(symbol);
   PairState[index] = state;
   
   // Choose strategy based on market state
   STRATEGY_TYPE strategy = STRATEGY_NONE;
   int signal = 0;
   
   switch(state) {
      case STATE_TREND_UP:
      case STATE_TREND_DOWN:
         if(UseTrendStrategy) {
            strategy = STRATEGY_TREND;
            signal = GetTrendSignal(symbol, state);
         }
         break;
         
      case STATE_RANGE:
         if(UseRangeStrategy) {
            strategy = STRATEGY_RANGE;
            signal = GetRangeSignal(symbol);
         }
         break;
         
      case STATE_BREAKOUT:
         if(UseBreakoutStrategy) {
            strategy = STRATEGY_BREAKOUT;
            signal = GetBreakoutSignal(symbol);
         }
         break;
   }
   
   // Update display based on signal
   if(signal > 0) {
      PairStatus[index] = "BUY";
      PairColor[index] = clrLime;
      ActiveStrategy[index] = strategy;
      
      if(PairTrades[index] == 0) {
         ExecuteTrade(symbol, OP_BUY, strategy);
         LastSignalTime[index] = TimeCurrent();
      }
   }
   else if(signal < 0) {
      PairStatus[index] = "SELL";
      PairColor[index] = clrRed;
      ActiveStrategy[index] = strategy;
      
      if(PairTrades[index] == 0) {
         ExecuteTrade(symbol, OP_SELL, strategy);
         LastSignalTime[index] = TimeCurrent();
      }
   }
   else {
      PairStatus[index] = MarketStateToString(state);
      PairColor[index] = GetStateColor(state);
      ActiveStrategy[index] = STRATEGY_NONE;
   }
}

// ===== MARKET STATE DETECTION =====
MARKET_STATE DetectMarketState(string symbol)
{
   // Get indicators
   double adx = iADX(symbol, PERIOD_H1, ADX_Period, PRICE_CLOSE, MODE_MAIN, 0);
   double atr = iATR(symbol, PERIOD_H1, 14, 0);
   double atr_avg = 0;
   for(int i = 1; i <= 20; i++) {
      atr_avg += iATR(symbol, PERIOD_H1, 14, i);
   }
   atr_avg /= 20;
   
   // Trend detection
   double ma20 = iMA(symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE, 0);
   double ma50 = iMA(symbol, PERIOD_H1, 50, 0, MODE_SMA, PRICE_CLOSE, 0);
   double price = MarketInfo(symbol, MODE_BID);
   
   // Strong trend
   if(adx > 25) {
      if(ma20 > ma50 && price > ma20) return STATE_TREND_UP;
      if(ma20 < ma50 && price < ma20) return STATE_TREND_DOWN;
   }
   
   // Breakout conditions
   if(atr > atr_avg * 1.5) {
      return STATE_BREAKOUT;
   }
   
   // Range conditions
   if(adx < 20 && atr < atr_avg) {
      return STATE_RANGE;
   }
   
   return STATE_CHOPPY;
}

// ===== STRATEGY SIGNALS =====

// TREND STRATEGY
int GetTrendSignal(string symbol, MARKET_STATE state)
{
   double ma_fast = iMA(symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ma_slow = iMA(symbol, PERIOD_H1, 50, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ma_fast_prev = iMA(symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE, 2);
   double ma_slow_prev = iMA(symbol, PERIOD_H1, 50, 0, MODE_SMA, PRICE_CLOSE, 2);
   
   // Buy signal
   if(state == STATE_TREND_UP && ma_fast_prev <= ma_slow_prev && ma_fast > ma_slow) {
      return 1;
   }
   
   // Sell signal
   if(state == STATE_TREND_DOWN && ma_fast_prev >= ma_slow_prev && ma_fast < ma_slow) {
      return -1;
   }
   
   return 0;
}

// RANGE STRATEGY
int GetRangeSignal(string symbol)
{
   double rsi = iRSI(symbol, PERIOD_H1, RSI_Period, PRICE_CLOSE, 0);
   double bb_upper = iBands(symbol, PERIOD_H1, 20, 2, 0, PRICE_CLOSE, MODE_UPPER, 0);
   double bb_lower = iBands(symbol, PERIOD_H1, 20, 2, 0, PRICE_CLOSE, MODE_LOWER, 0);
   double price = MarketInfo(symbol, MODE_BID);
   
   // Buy signal - oversold
   if(rsi < 30 && price <= bb_lower) {
      return 1;
   }
   
   // Sell signal - overbought
   if(rsi > 70 && price >= bb_upper) {
      return -1;
   }
   
   return 0;
}

// BREAKOUT STRATEGY
int GetBreakoutSignal(string symbol)
{
   // Get previous day high/low
   double prev_high = iHigh(symbol, PERIOD_D1, 1);
   double prev_low = iLow(symbol, PERIOD_D1, 1);
   double current_price = MarketInfo(symbol, MODE_BID);
   
   // Check for breakout with momentum
   double momentum = iMomentum(symbol, PERIOD_H1, 14, PRICE_CLOSE, 0);
   
   // Buy breakout
   if(current_price > prev_high && momentum > 100.5) {
      return 1;
   }
   
   // Sell breakout
   if(current_price < prev_low && momentum < 99.5) {
      return -1;
   }
   
   return 0;
}

// ===== TRADE EXECUTION =====
void ExecuteTrade(string symbol, int orderType, STRATEGY_TYPE strategy)
{
   // Calculate lot size
   double lotSize = CalculateLotSize(symbol);
   
   // Get pip value
   double pipValue = MarketInfo(symbol, MODE_POINT);
   if(MarketInfo(symbol, MODE_DIGITS) == 3 || MarketInfo(symbol, MODE_DIGITS) == 5) {
      pipValue *= 10;
   }
   
   double price, sl, tp;
   string comment = StrategyToString(strategy) + " #" + IntegerToString(TotalTrades + 1);
   
   RefreshRates();
   
   if(orderType == OP_BUY) {
      price = MarketInfo(symbol, MODE_ASK);
      sl = price - StopLoss * pipValue;
      tp = price + TakeProfit * pipValue;
      
      int ticket = OrderSend(symbol, OP_BUY, lotSize, price, 3, sl, tp, comment, MagicNumber, 0, clrGreen);
      
      if(ticket > 0) {
         TotalTrades++;
         UpdateStrategyCount(strategy);
         Print("✓ ", StrategyToString(strategy), " BUY ", symbol, " Lot:", lotSize);
         PlaySound("ok.wav");
      }
   }
   else if(orderType == OP_SELL) {
      price = MarketInfo(symbol, MODE_BID);
      sl = price + StopLoss * pipValue;
      tp = price - TakeProfit * pipValue;
      
      int ticket = OrderSend(symbol, OP_SELL, lotSize, price, 3, sl, tp, comment, MagicNumber, 0, clrRed);
      
      if(ticket > 0) {
         TotalTrades++;
         UpdateStrategyCount(strategy);
         Print("✓ ", StrategyToString(strategy), " SELL ", symbol, " Lot:", lotSize);
         PlaySound("ok.wav");
      }
   }
}

// ===== RISK MANAGEMENT =====
double CalculateLotSize(string symbol)
{
   double balance = AccountBalance();
   double riskAmount = balance * (RiskPercentage / 100.0);
   double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
   
   if(tickValue == 0) return 0.01;
   
   double lotSize = riskAmount / (StopLoss * tickValue * 10);
   double lotStep = MarketInfo(symbol, MODE_LOTSTEP);
   double minLot = MarketInfo(symbol, MODE_MINLOT);
   double maxLot = MarketInfo(symbol, MODE_MAXLOT);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   if(lotSize > 0.10) lotSize = 0.10; // Extra safety
   
   return NormalizeDouble(lotSize, 2);
}

bool CheckDailyLossLimit()
{
   // Reset daily tracking at new day
   if(iTime(Symbol(), PERIOD_D1, 0) > DailyStartTime) {
      DailyStartBalance = AccountBalance();
      DailyStartTime = iTime(Symbol(), PERIOD_D1, 0);
   }
   
   double currentLoss = (DailyStartBalance - AccountBalance()) / DailyStartBalance * 100;
   
   if(currentLoss >= MaxDailyLoss) {
      Comment("Daily loss limit reached: -", DoubleToString(currentLoss, 2), "%");
      return true;
   }
   
   return false;
}

// ===== TRADE MANAGEMENT =====
void ManageOpenTrades()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderMagicNumber() == MagicNumber) {
            // Check if trade is profitable
            if(OrderProfit() > 0) {
               // Could implement trailing stop here
            }
         }
      }
   }
}

// ===== DISPLAY FUNCTIONS =====
void SetupChart()
{
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'15,15,15');  // Dark gray
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, false);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, false);
}

void CreateAdvancedDashboard()
{
   int y = 10;
   
   // Main title with border
   CreateLabel("Title", "╔══════════ ADAPTIVE MARKET EA v3.1 ══════════╗", 10, y, clrGold, 11); y += 25;
   
   // Account section
   CreateLabel("AccTitle", "▼ ACCOUNT STATUS", 15, y, clrYellow, 10); y += 18;
   CreateLabel("Balance", "Balance: $0.00", 20, y, clrWhite, 9); y += 16;
   CreateLabel("Equity", "Equity: $0.00", 20, y, clrWhite, 9); y += 16;
   CreateLabel("Profit", "P/L: $0.00", 20, y, clrWhite, 9); y += 16;
   CreateLabel("DailyPL", "Daily: $0.00", 20, y, clrWhite, 9); y += 25;
   
   // Strategy section
   CreateLabel("StratTitle", "▼ STRATEGY PERFORMANCE", 15, y, clrYellow, 10); y += 18;
   CreateLabel("TrendPerf", "Trend: 0 trades", 20, y, clrWhite, 9); y += 16;
   CreateLabel("RangePerf", "Range: 0 trades", 20, y, clrWhite, 9); y += 16;
   CreateLabel("BreakPerf", "Break: 0 trades", 20, y, clrWhite, 9); y += 25;
   
   // Statistics
   CreateLabel("StatsTitle", "▼ STATISTICS", 15, y, clrYellow, 10); y += 18;
   CreateLabel("WinRate", "Win Rate: 0%", 20, y, clrWhite, 9); y += 16;
   CreateLabel("OpenTrades", "Open: 0/5", 20, y, clrWhite, 9); y += 25;
   
   // Create improved pair grid with buttons
   CreateImprovedPairGrid();
}

void CreateImprovedPairGrid()
{
   int startX = 300;  // Moved further right
   int startY = 40;   // Lower start
   int boxW = 130;    // Even wider boxes
   int boxH = 55;     // Even taller boxes
   int cols = 4;      // Only 4 columns for more space
   
   // Grid title
   CreateLabel("GridTitle", "===== CURRENCY PAIR MONITOR (Click ? to open charts) =====", 
               startX, startY - 25, clrAqua, 10);
   
   for(int i = 0; i < TotalPairs; i++) {
      int col = i % cols;
      int row = i / cols;
      int x = startX + (col * (boxW + 15));  // Much more spacing between columns
      int y = startY + (row * (boxH + 8));   // More spacing between rows
      
      // Create button for chart
      string btnName = "BTN_" + IntegerToString(i);
      ObjectCreate(0, btnName, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, btnName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, btnName, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, btnName, OBJPROP_XSIZE, 25);
      ObjectSetInteger(0, btnName, OBJPROP_YSIZE, 18);
      ObjectSetString(0, btnName, OBJPROP_TEXT, "?");  // Changed to ?
      ObjectSetString(0, btnName, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, btnName, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, btnName, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR, clrDarkGray);
      ObjectSetInteger(0, btnName, OBJPROP_BORDER_COLOR, clrGray);
      
      // Pair name (moved right for button)
      CreateLabel("P_" + IntegerToString(i), TradePairs[i], x + 30, y + 1, clrWhite, 10);
      
      // Status below pair name with more space
      CreateLabel("S_" + IntegerToString(i), "WAIT", x + 30, y + 18, clrGray, 9);
      
      // Spread info with more space
      CreateLabel("SP_" + IntegerToString(i), "Sp:0.0", x + 30, y + 35, clrGray, 8);
   }
}

void UpdateMainDashboard()
{
   static datetime lastUpdate = 0;
   if(TimeCurrent() - lastUpdate < 1) return;
   lastUpdate = TimeCurrent();
   
   double pl = GetTotalProfit();
   double dailyPL = AccountBalance() - DailyStartBalance;
   
   ObjectSetString(0, "Balance", OBJPROP_TEXT, "Balance: $" + DoubleToString(AccountBalance(), 2));
   ObjectSetString(0, "Equity", OBJPROP_TEXT, "Equity: $" + DoubleToString(AccountEquity(), 2));
   ObjectSetString(0, "Profit", OBJPROP_TEXT, "P/L: $" + DoubleToString(pl, 2));
   ObjectSetInteger(0, "Profit", OBJPROP_COLOR, pl >= 0 ? clrLime : clrRed);
   ObjectSetString(0, "DailyPL", OBJPROP_TEXT, "Daily: $" + DoubleToString(dailyPL, 2));
   ObjectSetInteger(0, "DailyPL", OBJPROP_COLOR, dailyPL >= 0 ? clrLime : clrRed);
   
   double winRate = TotalTrades > 0 ? (WinTrades * 100.0 / TotalTrades) : 0;
   ObjectSetString(0, "WinRate", OBJPROP_TEXT, "Win Rate: " + DoubleToString(winRate, 1) + "%");
   ObjectSetString(0, "OpenTrades", OBJPROP_TEXT, "Open: " + IntegerToString(CountAllTrades()) + "/5");
   
   // Update pair displays with better formatting
   for(int i = 0; i < TotalPairs; i++) {
      // Update status
      ObjectSetString(0, "S_" + IntegerToString(i), OBJPROP_TEXT, PairStatus[i]);
      ObjectSetInteger(0, "S_" + IntegerToString(i), OBJPROP_COLOR, PairColor[i]);
      
      // Update pair name color
      ObjectSetInteger(0, "P_" + IntegerToString(i), OBJPROP_COLOR, 
                      PairTrades[i] > 0 ? clrAqua : clrWhite);
      
      // Update spread
      ObjectSetString(0, "SP_" + IntegerToString(i), OBJPROP_TEXT, 
                     "Sp:" + DoubleToString(PairSpread[i], 1));
      
      // Update button color based on state
      string btnName = "BTN_" + IntegerToString(i);
      if(PairTrades[i] > 0) {
         ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR, clrLime);
      } else if(PairColor[i] == clrRed || PairColor[i] == clrLime) {
         ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR, clrYellow);
      } else {
         ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR, clrSilver);
      }
   }
}

void UpdateStrategyPanel()
{
   ObjectSetString(0, "TrendPerf", OBJPROP_TEXT, "Trend: " + IntegerToString(TrendTrades) + " trades");
   ObjectSetString(0, "RangePerf", OBJPROP_TEXT, "Range: " + IntegerToString(RangeTrades) + " trades");
   ObjectSetString(0, "BreakPerf", OBJPROP_TEXT, "Break: " + IntegerToString(BreakoutTrades) + " trades");
}

// ===== HELPER FUNCTIONS =====
int CountAllTrades()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderMagicNumber() == MagicNumber) count++;
      }
   }
   return count;
}

int CountPairTrades(string symbol)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderMagicNumber() == MagicNumber && OrderSymbol() == symbol) count++;
      }
   }
   return count;
}

double GetTotalProfit()
{
   double profit = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderMagicNumber() == MagicNumber) {
            profit += OrderProfit() + OrderSwap() + OrderCommission();
         }
      }
   }
   return profit;
}

string MarketStateToString(MARKET_STATE state)
{
   switch(state) {
      case STATE_TREND_UP:   return "BULL";      // Clear bullish
      case STATE_TREND_DOWN: return "BEAR";      // Clear bearish
      case STATE_RANGE:      return "RANGE";
      case STATE_BREAKOUT:   return "BREAK";
      default:               return "WAIT";
   }
}


string StrategyToString(STRATEGY_TYPE strategy)
{
   switch(strategy) {
      case STRATEGY_TREND: return "TREND";
      case STRATEGY_RANGE: return "RANGE";
      case STRATEGY_BREAKOUT: return "BREAK";
      default: return "NONE";
   }
}

color GetStateColor(MARKET_STATE state)
{
   switch(state) {
      case STATE_TREND_UP: return clrLimeGreen;
      case STATE_TREND_DOWN: return clrOrangeRed;
      case STATE_RANGE: return clrYellow;
      case STATE_BREAKOUT: return clrMagenta;
      default: return clrGray;
   }
}

void UpdateStrategyCount(STRATEGY_TYPE strategy)
{
   switch(strategy) {
      case STRATEGY_TREND: TrendTrades++; break;
      case STRATEGY_RANGE: RangeTrades++; break;
      case STRATEGY_BREAKOUT: BreakoutTrades++; break;
   }
}

void CreateLabel(string name, string text, int x, int y, color clr, int size)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}