//+------------------------------------------------------------------+
//|                                               ApexScalperPro.mq5  |
//|                      Professional MT5 Expert Advisor - Version 0.1|
//+------------------------------------------------------------------+
#property strict
#property version   "0.10"
#property description "ApexScalperPro Version 0.1 - foundation milestone"

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                  |
//+------------------------------------------------------------------+
input string InpSymbols                 = "";          // Symbols to manage, comma separated. Empty = current symbol
input ENUM_TIMEFRAMES InpTimeframe      = PERIOD_M5;   // Working timeframe
input ulong  InpMagicNumber             = 26071901;    // Expert magic number
input double InpFixedLot                = 0.10;        // Fixed lot size for Version 0.1
input int    InpMaxSpreadPoints         = 30;          // Maximum allowed spread in points
input int    InpDeviationPoints         = 10;          // Maximum trade deviation in points
input bool   InpEnableTrading           = false;       // Master trading switch
input bool   InpEnableDashboard         = true;        // Show dashboard
input bool   InpEnableLogging           = true;        // Print runtime logs
input string InpLogPrefix               = "ApexScalperPro"; // Log prefix

//+------------------------------------------------------------------+
//| Logger                                                           |
//+------------------------------------------------------------------+
class CLogger
{
private:
   string m_prefix;
   bool   m_enabled;

public:
   void Init(const string prefix, const bool enabled)
   {
      m_prefix  = prefix;
      m_enabled = enabled;
   }

   void Info(const string message)
   {
      if(m_enabled)
         PrintFormat("[%s][INFO] %s", m_prefix, message);
   }

   void Warn(const string message)
   {
      if(m_enabled)
         PrintFormat("[%s][WARN] %s", m_prefix, message);
   }

   void Error(const string message)
   {
      PrintFormat("[%s][ERROR] %s", m_prefix, message);
   }
};

//+------------------------------------------------------------------+
//| Market data manager                                              |
//+------------------------------------------------------------------+
class CMarketDataManager
{
private:
   string m_symbols[];
   int    m_symbol_count;

   string Trim(const string value)
   {
      string result = value;
      StringTrimLeft(result);
      StringTrimRight(result);
      return result;
   }

public:
   CMarketDataManager()
   {
      m_symbol_count = 0;
   }

   bool Init(const string configured_symbols, const string fallback_symbol, CLogger &logger)
   {
      ArrayResize(m_symbols, 0);
      m_symbol_count = 0;

      string source = Trim(configured_symbols);
      if(source == "")
         source = fallback_symbol;

      string parts[];
      const int total = StringSplit(source, ',', parts);
      if(total <= 0)
      {
         logger.Error("No trade symbols were configured.");
         return false;
      }

      for(int index = 0; index < total; index++)
      {
         const string symbol = Trim(parts[index]);
         if(symbol == "")
            continue;

         if(!SymbolSelect(symbol, true))
         {
            logger.Error(StringFormat("Unable to select symbol '%s'.", symbol));
            return false;
         }

         const int next_size = m_symbol_count + 1;
         ArrayResize(m_symbols, next_size);
         m_symbols[m_symbol_count] = symbol;
         m_symbol_count = next_size;
      }

      if(m_symbol_count == 0)
      {
         logger.Error("Symbol list is empty after parsing input parameters.");
         return false;
      }

      logger.Info(StringFormat("Market data initialized for %d symbol(s).", m_symbol_count));
      return true;
   }

   int SymbolCount()
   {
      return m_symbol_count;
   }

   string SymbolAt(const int index)
   {
      if(index < 0 || index >= m_symbol_count)
         return "";
      return m_symbols[index];
   }

   bool RefreshSymbol(const string symbol, MqlTick &tick, CLogger &logger)
   {
      if(!SymbolInfoTick(symbol, tick))
      {
         logger.Warn(StringFormat("No tick data available for %s.", symbol));
         return false;
      }

      return true;
   }

   int SpreadPoints(const string symbol)
   {
      return (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   }
};

//+------------------------------------------------------------------+
//| Risk manager skeleton                                            |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   int    m_max_spread_points;
   double m_fixed_lot;

public:
   void Init(const int max_spread_points, const double fixed_lot)
   {
      m_max_spread_points = max_spread_points;
      m_fixed_lot         = fixed_lot;
   }

   bool IsSpreadAllowed(const string symbol, const int spread_points, CLogger &logger)
   {
      if(spread_points > m_max_spread_points)
      {
         logger.Warn(StringFormat("%s spread blocked: %d points exceeds limit %d.", symbol, spread_points, m_max_spread_points));
         return false;
      }

      return true;
   }

   double NormalizeLot(const string symbol, const double requested_lot)
   {
      const double min_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      const double max_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      const double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      double lot = MathMax(min_lot, MathMin(max_lot, requested_lot));
      if(lot_step > 0.0)
         lot = MathFloor(lot / lot_step) * lot_step;

      return NormalizeDouble(lot, 2);
   }

   double LotSize(const string symbol)
   {
      return NormalizeLot(symbol, m_fixed_lot);
   }
};

//+------------------------------------------------------------------+
//| Trade engine                                                     |
//+------------------------------------------------------------------+
class CTradeEngine
{
private:
   CTrade m_trade;
   ulong  m_magic_number;
   int    m_deviation_points;
   bool   m_enabled;

public:
   void Init(const ulong magic_number, const int deviation_points, const bool enabled)
   {
      m_magic_number     = magic_number;
      m_deviation_points = deviation_points;
      m_enabled          = enabled;

      m_trade.SetExpertMagicNumber(m_magic_number);
      m_trade.SetDeviationInPoints(m_deviation_points);
      m_trade.SetTypeFillingBySymbol(_Symbol);
   }

   bool TradingEnabled()
   {
      return m_enabled;
   }

   // Version 0.1 intentionally exposes execution plumbing only; strategy entries arrive in later milestones.
   bool Buy(const string symbol, const double lot, const string comment, CLogger &logger)
   {
      if(!m_enabled)
      {
         logger.Info("Buy request ignored because trading is disabled.");
         return false;
      }

      m_trade.SetTypeFillingBySymbol(symbol);
      ResetLastError();
      if(!m_trade.Buy(lot, symbol, 0.0, 0.0, 0.0, comment))
      {
         logger.Error(StringFormat("Buy failed for %s. Retcode=%u LastError=%d", symbol, m_trade.ResultRetcode(), GetLastError()));
         return false;
      }

      logger.Info(StringFormat("Buy placed for %s, lot %.2f.", symbol, lot));
      return true;
   }

   bool Sell(const string symbol, const double lot, const string comment, CLogger &logger)
   {
      if(!m_enabled)
      {
         logger.Info("Sell request ignored because trading is disabled.");
         return false;
      }

      m_trade.SetTypeFillingBySymbol(symbol);
      ResetLastError();
      if(!m_trade.Sell(lot, symbol, 0.0, 0.0, 0.0, comment))
      {
         logger.Error(StringFormat("Sell failed for %s. Retcode=%u LastError=%d", symbol, m_trade.ResultRetcode(), GetLastError()));
         return false;
      }

      logger.Info(StringFormat("Sell placed for %s, lot %.2f.", symbol, lot));
      return true;
   }
};

//+------------------------------------------------------------------+
//| Dashboard skeleton                                               |
//+------------------------------------------------------------------+
class CDashboard
{
private:
   bool m_enabled;

public:
   void Init(const bool enabled)
   {
      m_enabled = enabled;
   }

   void Render(CMarketDataManager &market_data, CTradeEngine &trade_engine)
   {
      if(!m_enabled)
         return;

      string text = "ApexScalperPro v0.1\n";
      text += StringFormat("Trading: %s\n", trade_engine.TradingEnabled() ? "enabled" : "disabled");
      text += StringFormat("Symbols: %d\n", market_data.SymbolCount());
      text += StringFormat("Timeframe: %s\n", EnumToString(InpTimeframe));
      text += "Status: foundation initialized";
      Comment(text);
   }

   void Clear()
   {
      if(m_enabled)
         Comment("");
   }
};

//+------------------------------------------------------------------+
//| Global module instances                                          |
//+------------------------------------------------------------------+
CLogger            g_logger;
CMarketDataManager g_market_data;
CRiskManager       g_risk_manager;
CTradeEngine       g_trade_engine;
CDashboard         g_dashboard;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_logger.Init(InpLogPrefix, InpEnableLogging);
   g_logger.Info("Initializing ApexScalperPro Version 0.1.");

   if(!g_market_data.Init(InpSymbols, _Symbol, g_logger))
      return INIT_FAILED;

   g_risk_manager.Init(InpMaxSpreadPoints, InpFixedLot);
   g_trade_engine.Init(InpMagicNumber, InpDeviationPoints, InpEnableTrading);
   g_dashboard.Init(InpEnableDashboard);
   g_dashboard.Render(g_market_data, g_trade_engine);

   g_logger.Info("Initialization completed successfully.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   for(int index = 0; index < g_market_data.SymbolCount(); index++)
   {
      const string symbol = g_market_data.SymbolAt(index);
      if(symbol == "")
         continue;

      MqlTick tick;
      if(!g_market_data.RefreshSymbol(symbol, tick, g_logger))
         continue;

      const int spread_points = g_market_data.SpreadPoints(symbol);
      if(!g_risk_manager.IsSpreadAllowed(symbol, spread_points, g_logger))
         continue;

      // Strategy, scanner, and decision engine are intentionally added in later milestones.
      const double lot = g_risk_manager.LotSize(symbol);
      if(lot <= 0.0)
         g_logger.Warn(StringFormat("Calculated lot size for %s is invalid: %.2f", symbol, lot));
   }

   g_dashboard.Render(g_market_data, g_trade_engine);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_dashboard.Clear();
   g_logger.Info(StringFormat("ApexScalperPro deinitialized. Reason=%d", reason));
}
