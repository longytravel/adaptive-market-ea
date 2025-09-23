#ifndef __ADAPTIVE_DASHBOARD_MQH__
#define __ADAPTIVE_DASHBOARD_MQH__

#ifdef MAX_SYMBOLS
#define DASHBOARD_MAX_SYMBOLS MAX_SYMBOLS
#else
#define DASHBOARD_MAX_SYMBOLS 16
#endif

struct DashboardSymbolInfo
{
   string  name;
   string  regime;
   double  score;
   double  trendScore;
   double  microScore;
   double  reversionScore;
   double  breakoutScore;
   double  bias;
   double  llmBias;
   double  weightTrend;
   double  weightMicro;
   double  weightReversion;
   double  weightBreakout;
   int     direction;
   double  lots;
   double  openProfit;
   double  spreadPoints;
   bool    spreadBlocked;
   bool    newsBlocked;
   string  signal;
   string  reasoning;
};

struct DashboardSnapshot
{
   datetime now;
   double   balance;
   double   equity;
   double   dailyPnL;
   double   dailyPnLPercent;
   bool     tradingHalted;
   double   globalSentiment;
   double   globalRiskMultiplier;
   double   globalRiskCap;
   string   modelUpdated;
   datetime lastModelLoad;
   string   modelError;
   string   lossLimitInfo;
   int      symbolCount;
   DashboardSymbolInfo symbols[DASHBOARD_MAX_SYMBOLS];
};

class AdaptiveDashboard
{
private:
   int     m_chartId;
   string  m_prefix;
   bool    m_ready;
   string  m_lastFingerprint;

   bool HasActivePositions(const DashboardSnapshot &snap) const
   {
      for(int idx=0; idx<snap.symbolCount; idx++)
      {
         if(snap.symbols[idx].direction != 0)
            return true;
      }
      return false;
   }

   string BuildPositionLine(const DashboardSymbolInfo &info) const
   {
      string direction = (info.direction > 0) ? "LONG" : "SHORT";
      string profitText = StringFormat("P&L: $%.2f", info.openProfit);
      return StringFormat("%s %s %.2f lots | %s | %s",
                          info.name,
                          direction,
                          info.lots,
                          profitText,
                          info.reasoning);
   }

   string BuildSignalLine(const DashboardSymbolInfo &info) const
   {
      string blocks = "";
      if(info.newsBlocked)
         blocks += "News Block ";
      if(info.spreadBlocked)
         blocks += "High Spread ";

      return StringFormat("%s: %s | %s %s",
                          info.name,
                          info.signal,
                          info.reasoning,
                          blocks);
   }

   color GetSignalColor(const string signal) const
   {
      if(signal == "BUY")
         return clrLightGreen;
      else if(signal == "SELL")
         return clrOrange;
      else if(signal == "EXIT")
         return clrYellow;
      else
         return clrWhite;
   }

   string Fingerprint(const DashboardSnapshot &snap) const
   {
      string fp = StringFormat("%.2f|%.2f|%.2f|%.2f|%d|%.3f|%.3f|%.3f|%s|%d|%s",
                               snap.balance,
                               snap.equity,
                               snap.dailyPnL,
                               snap.dailyPnLPercent,
                               (int)snap.tradingHalted,
                               snap.globalSentiment,
                               snap.globalRiskMultiplier,
                               snap.globalRiskCap,
                               snap.modelUpdated,
                               snap.symbolCount,
                               snap.modelError);
      for(int i=0; i<snap.symbolCount; i++)
      {
         DashboardSymbolInfo info = snap.symbols[i];
         fp += StringFormat("|%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%d|%.2f",
                             info.name,
                             info.score,
                             info.trendScore,
                             info.microScore,
                             info.reversionScore,
                             info.breakoutScore,
                             info.openProfit,
                             info.direction,
                             info.lots);
      }
      return fp;
   }

   void EnsureBackground(const int width, const int height)
   {
      string name = m_prefix + "_bg";
      if(ObjectFind(m_chartId, name) == -1)
      {
         ObjectCreate(m_chartId, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, name, OBJPROP_BGCOLOR, clrBlack);  // Use BGCOLOR for fill
         ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clrBlack);   // Border color
         ObjectSetInteger(m_chartId, name, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(m_chartId, name, OBJPROP_BACK, false);
         ObjectSetInteger(m_chartId, name, OBJPROP_FILL, true);        // Enable fill
      }
      ObjectSetInteger(m_chartId, name, OBJPROP_XDISTANCE, 6);
      ObjectSetInteger(m_chartId, name, OBJPROP_YDISTANCE, 18);
      ObjectSetInteger(m_chartId, name, OBJPROP_XSIZE, width);
      ObjectSetInteger(m_chartId, name, OBJPROP_YSIZE, height);
   }

   void SetLabel(const string key, const int x, const int y, const string text, const int size = 9, const color clr = clrBlack)
   {
      string name = m_prefix + "_" + key;
      if(ObjectFind(m_chartId, name) == -1)
      {
         ObjectCreate(m_chartId, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetString(m_chartId, name, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(m_chartId, name, OBJPROP_FONTSIZE, size);
      }
      ObjectSetInteger(m_chartId, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chartId, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
      ObjectSetString(m_chartId, name, OBJPROP_TEXT, text);
   }

   void DestroyAll()
   {
      int total = ObjectsTotal(m_chartId, -1, -1);
      for(int i=total-1; i>=0; i--)
      {
         string name = ObjectName(m_chartId, i);
         if(StringFind(name, m_prefix) == 0)
            ObjectDelete(m_chartId, name);
      }
   }

public:
   AdaptiveDashboard(): m_chartId(0), m_prefix("AMDash"), m_ready(false) {}

   void Init(const int chartId)
   {
      m_chartId = chartId;
      m_ready = true;
      m_lastFingerprint = "";
   }

   void Deinit()
   {
      if(!m_ready)
         return;
      DestroyAll();
      m_ready = false;
      m_lastFingerprint = "";
   }

   void Update(const DashboardSnapshot &snap)
   {
      if(!m_ready)
         return;
      string fp = Fingerprint(snap);
      if(fp == m_lastFingerprint)
         return;
      m_lastFingerprint = fp;

      const int lineHeight = 20;
      const int baseX = 25;
      const int sectionGap = 15;
      int y = 35;
      int panelWidth = 850;
      int panelHeight = 250 + snap.symbolCount * 25; // Much bigger background
      EnsureBackground(panelWidth, panelHeight);

      // Section 1: Title
      string title = StringFormat("Adaptive Market EA Dashboard - %s", TimeToString(snap.now, TIME_MINUTES));
      SetLabel("title", baseX, y, title, 12, clrWhite);
      y += lineHeight + sectionGap;

      // Section 2: Account Overview - Each on separate line for clarity
      string balanceText = StringFormat("Balance: $%.2f", snap.balance);
      SetLabel("balance", baseX, y, balanceText, 11, clrWhite);
      y += lineHeight;

      string equityText = StringFormat("Equity: $%.2f", snap.equity);
      SetLabel("equity", baseX, y, equityText, 11, clrWhite);
      y += lineHeight;

      string pnlText = StringFormat("Daily P&L: $%.2f (%.2f%%)", snap.dailyPnL, snap.dailyPnLPercent);
      SetLabel("pnl", baseX, y, pnlText, 11, (snap.dailyPnL >= 0 ? clrLightGreen : clrOrange));
      y += lineHeight;

      string riskStatus = snap.tradingHalted ? "TRADING HALTED" : "NORMAL";
      color riskColor = snap.tradingHalted ? clrRed : clrLightGreen;
      SetLabel("risk_status", baseX, y, "Risk Status: " + riskStatus, 10, riskColor);
      y += lineHeight + sectionGap;

      // Section 3: Active Positions Header
      if(HasActivePositions(snap))
      {
         SetLabel("pos_header", baseX, y, "ACTIVE POSITIONS:", 11, clrWhite);
         y += lineHeight;

         for(int k=0; k<snap.symbolCount; k++)
         {
            if(snap.symbols[k].direction != 0)
            {
               string positionLine = BuildPositionLine(snap.symbols[k]);
               color posColor = (snap.symbols[k].openProfit >= 0 ? clrLightGreen : clrOrange);
               SetLabel("pos" + IntegerToString(k), baseX + 15, y, positionLine, 10, posColor);
               y += lineHeight;
            }
         }
         y += sectionGap;
      }

      // Section 4: Current Signals Header
      SetLabel("sig_header", baseX, y, "CURRENT SIGNALS:", 11, clrWhite);
      y += lineHeight;

      for(int j=0; j<snap.symbolCount; j++)
      {
         string signalLine = BuildSignalLine(snap.symbols[j]);
         color sigColor = GetSignalColor(snap.symbols[j].signal);
         SetLabel("sig" + IntegerToString(j), baseX + 15, y, signalLine, 10, sigColor);
         y += lineHeight;
      }
      y += sectionGap;

      // Section 5: System Status
      string modelStatus = StringLen(snap.modelError) == 0 ? "Model: OK" : "Model: " + snap.modelError;
      color modelColor = StringLen(snap.modelError) == 0 ? clrLightGreen : clrOrange;
      SetLabel("model_status", baseX, y, modelStatus, 9, modelColor);
      y += lineHeight;

      if(snap.lastModelLoad > 0)
      {
         string lastUpdate = "Last Update: " + TimeToString(snap.lastModelLoad, TIME_MINUTES);
         SetLabel("model_update", baseX, y, lastUpdate, 9, clrWhite);
      }
   }
};

#endif


