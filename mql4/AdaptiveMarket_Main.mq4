//+------------------------------------------------------------------+
//|                                          AdaptiveMarket_Main.mq4 |
//|                                    Your Adaptive Market EA v2.0 |
//|                               Phase 3: Multi-Pair & Dashboard   |
//+------------------------------------------------------------------+
#property copyright "Adaptive Market EA"
#property version   "2.00"
#property strict

// ===== INPUT PARAMETERS =====
input double RiskPercentage = 1.0;        // Risk % per trade
input int    MaxConcurrentTrades = 5;     // Maximum open trades
input int    StopLoss = 50;               // Stop Loss in pips
input int    TakeProfit = 100;            // Take Profit in pips
input double MinLotSize = 0.01;           // Minimum lot size
input double MaxLotSize = 0.10;           // Maximum lot size
input bool   TradeAllPairs = true;        // Trade all pairs

// ===== GLOBAL VARIABLES =====
string EA_NAME = "Adaptive Market EA";
int    MagicNumber = 123456;

// Forex pairs to monitor
string TradePairs[] = {
   "EURUSD", "GBPUSD", "USDJPY", "USDCHF", "USDCAD", "AUDUSD", "NZDUSD",
   "EURJPY", "GBPJPY", "EURGBP", "EURAUD", "EURCAD", "GBPAUD", "GBPCAD"
};
int TotalPairs = 14;  // Start with 14 major pairs

// Arrays to store pair data
double PairSpread[];
double PairTrend[];
double PairSignal[];
datetime PairLastCheck[];
int PairOpenTrades[];
string PairStatus[];
color PairColor[];

// Statistics
int TotalTrades = 0;
int WinningTrades = 0;
double TodayProfit = 0;
datetime TodayStart;

// ===== INITIALIZATION =====
int OnInit()
{
   Print("=================================");
   Print(EA_NAME + " v2.0 - MULTI-PAIR");
   Print("Monitoring ", TotalPairs, " pairs");
   Print("=================================");
   
   // Initialize arrays
   ArrayResize(PairSpread, TotalPairs);
   ArrayResize(PairTrend, TotalPairs);
   ArrayResize(PairSignal, TotalPairs);
   ArrayResize(PairLastCheck, TotalPairs);
   ArrayResize(PairOpenTrades, TotalPairs);
   ArrayResize(PairStatus, TotalPairs);
   ArrayResize(PairColor, TotalPairs);
   
   // Set up chart
   SetupChart();
   
   // Create main dashboard
   CreateMainDashboard();
   
   // Create pair grid
   CreatePairGrid();
   
   // Initialize today's start
   TodayStart = iTime(Symbol(), PERIOD_D1, 0);
   
   return(INIT_SUCCEEDED);
}

// ===== DEINITIALIZATION =====
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0);
   Print("EA Stopped. Total trades: ", TotalTrades);
}

// ===== MAIN TICK FUNCTION =====
void OnTick()
{
   // Update main stats
   UpdateMainDashboard();
   
   // Check each pair
   for(int i = 0; i < TotalPairs; i++) {
      CheckPair(i);
      UpdatePairDisplay(i);
   }
   
   // Manage open trades
   ManageOpenTrades();
}

// ===== PAIR ANALYSIS =====
void CheckPair(int pairIndex)
{
   string symbol = TradePairs[pairIndex];
   
   // Skip if symbol doesn't exist
   if(MarketInfo(symbol, MODE_BID) == 0) {
      PairStatus[pairIndex] = "OFFLINE";
      PairColor[pairIndex] = clrGray;
      return;
   }
   
   // Check only once per minute per pair
   if(TimeCurrent() - PairLastCheck[pairIndex] < 60) return;
   PairLastCheck[pairIndex] = TimeCurrent();
   
   // Get spread
   double spread = MarketInfo(symbol, MODE_SPREAD) / 10.0;
   PairSpread[pairIndex] = spread;
   
   // Check if we can trade this pair
   PairOpenTrades[pairIndex] = CountPairTrades(symbol);
   if(CountAllTrades() >= MaxConcurrentTrades) {
      PairStatus[pairIndex] = "MAX";
      PairColor[pairIndex] = clrYellow;
      return;
   }
   
   if(PairOpenTrades[pairIndex] > 0) {
      PairStatus[pairIndex] = "IN TRADE";
      PairColor[pairIndex] = clrAqua;
      return;
   }
   
   // Check for signals
   int signal = GetSignal(symbol);
   PairSignal[pairIndex] = signal;
   
   if(signal == 1) {
      PairStatus[pairIndex] = "BUY SIGNAL";
      PairColor[pairIndex] = clrLime;
      if(spread < 2.0 && TradeAllPairs) {
         OpenPairTrade(symbol, OP_BUY);
      }
   } else if(signal == -1) {
      PairStatus[pairIndex] = "SELL SIGNAL";
      PairColor[pairIndex] = clrRed;
      if(spread < 2.0 && TradeAllPairs) {
         OpenPairTrade(symbol, OP_SELL);
      }
   } else {
      PairStatus[pairIndex] = "WAITING";
      PairColor[pairIndex] = clrWhite;
   }
}

// ===== GET TRADING SIGNAL =====
int GetSignal(string symbol)
{
   // Simple MA crossover for now
   double ma_fast = iMA(symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ma_slow = iMA(symbol, PERIOD_H1, 50, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ma_fast_prev = iMA(symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE, 2);
   double ma_slow_prev = iMA(symbol, PERIOD_H1, 50, 0, MODE_SMA, PRICE_CLOSE, 2);
   
   // Buy signal
   if(ma_fast_prev <= ma_slow_prev && ma_fast > ma_slow) {
      return 1;
   }
   
   // Sell signal
   if(ma_fast_prev >= ma_slow_prev && ma_fast < ma_slow) {
      return -1;
   }
   
   return 0;  // No signal
}

// ===== OPEN TRADE FOR SPECIFIC PAIR =====
void OpenPairTrade(string symbol, int orderType)
{
   // Calculate lot size
   double lotSize = CalculatePairLotSize(symbol);
   
   // Get pip value for this pair
   double pipValue = MarketInfo(symbol, MODE_POINT);
   if(MarketInfo(symbol, MODE_DIGITS) == 3 || MarketInfo(symbol, MODE_DIGITS) == 5) {
      pipValue *= 10;
   }
   
   double price, sl, tp;
   
   RefreshRates();
   
   if(orderType == OP_BUY) {
      price = MarketInfo(symbol, MODE_ASK);
      sl = price - StopLoss * pipValue;
      tp = price + TakeProfit * pipValue;
      
      int ticket = OrderSend(symbol, OP_BUY, lotSize, price, 3, sl, tp, 
                            EA_NAME, MagicNumber, 0, clrGreen);
      
      if(ticket > 0) {
         TotalTrades++;
         Print("✓ BUY ", symbol, " Lot:", lotSize);
         PlaySound("ok.wav");
      }
   } else {
      price = MarketInfo(symbol, MODE_BID);
      sl = price + StopLoss * pipValue;
      tp = price - TakeProfit * pipValue;
      
      int ticket = OrderSend(symbol, OP_SELL, lotSize, price, 3, sl, tp, 
                            EA_NAME, MagicNumber, 0, clrRed);
      
      if(ticket > 0) {
         TotalTrades++;
         Print("✓ SELL ", symbol, " Lot:", lotSize);
         PlaySound("ok.wav");
      }
   }
}

// ===== LOT SIZE CALCULATION =====
double CalculatePairLotSize(string symbol)
{
   double accountBalance = AccountBalance();
   double riskAmount = accountBalance * (RiskPercentage / 100.0);
   
   double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
   if(tickValue == 0) return MinLotSize;
   
   double lotSize = riskAmount / (StopLoss * tickValue * 10);
   
   // Normalize
   double lotStep = MarketInfo(symbol, MODE_LOTSTEP);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   if(lotSize < MinLotSize) lotSize = MinLotSize;
   if(lotSize > MaxLotSize) lotSize = MaxLotSize;
   
   return NormalizeDouble(lotSize, 2);
}

// ===== TRADE MANAGEMENT =====
void ManageOpenTrades()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderMagicNumber() == MagicNumber) {
            // Could add trailing stop here
         }
      }
   }
}

// ===== COUNTING FUNCTIONS =====
int CountAllTrades()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderMagicNumber() == MagicNumber) {
            count++;
         }
      }
   }
   return count;
}

int CountPairTrades(string symbol)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderMagicNumber() == MagicNumber && OrderSymbol() == symbol) {
            count++;
         }
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

// ===== DASHBOARD CREATION =====
void SetupChart()
{
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'20,20,20');
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, false);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, false);
}

void CreateMainDashboard()
{
   // Title
   CreateLabel("Title", "╔═══════════ ADAPTIVE MARKET EA v2.0 ═══════════╗", 
               10, 10, clrGold, 11);
   
   // Account info
   CreateLabel("AccInfo", "Account Info", 20, 35, clrYellow, 9);
   CreateLabel("Balance", "Balance: $0", 20, 50, clrWhite, 9);
   CreateLabel("Equity", "Equity: $0", 20, 65, clrWhite, 9);
   CreateLabel("Profit", "Profit: $0", 20, 80, clrWhite, 9);
   CreateLabel("Trades", "Open: 0/5", 20, 95, clrWhite, 9);
   
   // Performance
   CreateLabel("PerfInfo", "Performance", 150, 35, clrYellow, 9);
   CreateLabel("TodayPL", "Today: $0", 150, 50, clrWhite, 9);
   CreateLabel("WinRate", "Win Rate: 0%", 150, 65, clrWhite, 9);
   CreateLabel("TotalT", "Trades: 0", 150, 80, clrWhite, 9);
}

void CreatePairGrid()
{
   int startX = 20;
   int startY = 130;
   int boxWidth = 85;
   int boxHeight = 35;
   int columns = 7;
   
   CreateLabel("GridTitle", "═══ PAIR MONITORING GRID ═══", startX, startY - 15, clrAqua, 10);
   
   for(int i = 0; i < TotalPairs; i++) {
      int col = i % columns;
      int row = i / columns;
      int x = startX + (col * (boxWidth + 5));
      int y = startY + (row * (boxHeight + 5));
      
      // Pair name
      CreateLabel("Pair_" + IntegerToString(i), TradePairs[i], x, y, clrWhite, 8);
      
      // Status
      CreateLabel("Status_" + IntegerToString(i), "LOADING", x, y + 12, clrGray, 8);
      
      // Spread
      CreateLabel("Spread_" + IntegerToString(i), "Spread: 0.0", x, y + 24, clrGray, 7);
   }
}

// ===== UPDATE DISPLAYS =====
void UpdateMainDashboard()
{
   static datetime lastUpdate = 0;
   if(TimeCurrent() - lastUpdate < 1) return;
   lastUpdate = TimeCurrent();
   
   double profit = GetTotalProfit();
   
   ObjectSetString(0, "Balance", OBJPROP_TEXT, 
                   "Balance: $" + DoubleToString(AccountBalance(), 2));
   ObjectSetString(0, "Equity", OBJPROP_TEXT, 
                   "Equity: $" + DoubleToString(AccountEquity(), 2));
   ObjectSetString(0, "Profit", OBJPROP_TEXT, 
                   "Profit: $" + DoubleToString(profit, 2));
   ObjectSetInteger(0, "Profit", OBJPROP_COLOR, profit >= 0 ? clrLime : clrRed);
   
   ObjectSetString(0, "Trades", OBJPROP_TEXT, 
                   "Open: " + IntegerToString(CountAllTrades()) + "/" + 
                   IntegerToString(MaxConcurrentTrades));
   
   // Today's profit
   if(iTime(Symbol(), PERIOD_D1, 0) > TodayStart) {
      TodayProfit = 0;
      TodayStart = iTime(Symbol(), PERIOD_D1, 0);
   }
   ObjectSetString(0, "TodayPL", OBJPROP_TEXT, 
                   "Today: $" + DoubleToString(TodayProfit + profit, 2));
   
   double winRate = TotalTrades > 0 ? (WinningTrades * 100.0 / TotalTrades) : 0;
   ObjectSetString(0, "WinRate", OBJPROP_TEXT, 
                   "Win Rate: " + DoubleToString(winRate, 1) + "%");
   ObjectSetString(0, "TotalT", OBJPROP_TEXT, "Trades: " + IntegerToString(TotalTrades));
}

void UpdatePairDisplay(int i)
{
   static datetime lastUpdate[];
   if(ArraySize(lastUpdate) != TotalPairs) ArrayResize(lastUpdate, TotalPairs);
   
   if(TimeCurrent() - lastUpdate[i] < 2) return;
   lastUpdate[i] = TimeCurrent();
   
   // Update status and color
   ObjectSetString(0, "Status_" + IntegerToString(i), OBJPROP_TEXT, PairStatus[i]);
   ObjectSetInteger(0, "Status_" + IntegerToString(i), OBJPROP_COLOR, PairColor[i]);
   
   // Update spread
   ObjectSetString(0, "Spread_" + IntegerToString(i), OBJPROP_TEXT, 
                   "Sp: " + DoubleToString(PairSpread[i], 1));
   
   // Color the pair name based on trend
   if(PairSignal[i] > 0) {
      ObjectSetInteger(0, "Pair_" + IntegerToString(i), OBJPROP_COLOR, clrLime);
   } else if(PairSignal[i] < 0) {
      ObjectSetInteger(0, "Pair_" + IntegerToString(i), OBJPROP_COLOR, clrRed);
   } else {
      ObjectSetInteger(0, "Pair_" + IntegerToString(i), OBJPROP_COLOR, clrWhite);
   }
}

void CreateLabel(string name, string text, int x, int y, color clr, int fontSize)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}