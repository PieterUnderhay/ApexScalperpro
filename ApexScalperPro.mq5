//+------------------------------------------------------------------+
//|                                               ApexScalperPro.mq5  |
//|                      Professional MT5 Expert Advisor - Version 0.2|
//+------------------------------------------------------------------+
#property strict
#property version   "0.20"
#property description "ApexScalperPro Version 0.2 - Indicator Engine"

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
input int    InpFastEMAPeriod           = 9;           // Fast EMA period
input int    InpSlowEMAPeriod           = 21;          // Slow EMA period
input int    InpATRPeriod               = 14;          // ATR period
input int    InpADXPeriod               = 14;          // ADX period
input int    InpVolumeAverageBars       = 20;          // Volume average lookback bars
input double InpStrongADXLevel          = 25.0;        // Strong trend ADX threshold
input double InpVolatilityATRPoints     = 100.0;       // Volatile market ATR threshold in points
input double InpHighVolumeMultiplier    = 1.25;        // High volume multiplier over average

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
//| Indicator engine                                                 |
//+------------------------------------------------------------------+
class CIndicatorEngine
{
private:
   string m_symbols[];
   int    m_fast_ema_handles[];
   int    m_slow_ema_handles[];
   int    m_atr_handles[];
   int    m_adx_handles[];
   int    m_volume_handles[];
   int    m_symbol_count;
   ENUM_TIMEFRAMES m_timeframe;
   int    m_fast_ema_period;
   int    m_slow_ema_period;
   int    m_atr_period;
   int    m_adx_period;
   int    m_volume_average_bars;
   double m_strong_adx_level;
   double m_volatility_atr_points;
   double m_high_volume_multiplier;

   int FindSymbolIndex(const string symbol)
   {
      for(int index = 0; index < m_symbol_count; index++)
      {
         if(m_symbols[index] == symbol)
            return index;
      }

      return -1;
   }

   bool CreateHandle(const int handle, const string symbol, const string indicator_name, CLogger &logger)
   {
      if(handle != INVALID_HANDLE)
         return true;

      logger.Error(StringFormat("%s handle creation failed for %s. LastError=%d", indicator_name, symbol, GetLastError()));
      return false;
   }

   double IndicatorValue(const int handle, const int buffer_index, const int shift)
   {
      if(handle == INVALID_HANDLE)
         return 0.0;

      double values[];
      ArraySetAsSeries(values, true);
      if(CopyBuffer(handle, buffer_index, shift, 1, values) != 1)
         return 0.0;

      return values[0];
   }

   double IndicatorValueForSymbol(const string symbol, const int handles[], const int buffer_index, const int shift)
   {
      const int index = FindSymbolIndex(symbol);
      if(index < 0)
         return 0.0;

      return IndicatorValue(handles[index], buffer_index, shift);
   }

   long VolumeForSymbol(const string symbol, const int shift)
   {
      const int index = FindSymbolIndex(symbol);
      if(index < 0 || m_volume_handles[index] == INVALID_HANDLE)
         return 0;

      double volumes[];
      ArraySetAsSeries(volumes, true);
      if(CopyBuffer(m_volume_handles[index], 0, shift, 1, volumes) != 1)
         return 0;

      return (long)volumes[0];
   }

public:
   CIndicatorEngine()
   {
      m_symbol_count = 0;
      m_timeframe = PERIOD_CURRENT;
      m_fast_ema_period = 0;
      m_slow_ema_period = 0;
      m_atr_period = 0;
      m_adx_period = 0;
      m_volume_average_bars = 0;
      m_strong_adx_level = 0.0;
      m_volatility_atr_points = 0.0;
      m_high_volume_multiplier = 0.0;
   }

   bool Init(CMarketDataManager &market_data,
             const ENUM_TIMEFRAMES timeframe,
             const int fast_ema_period,
             const int slow_ema_period,
             const int atr_period,
             const int adx_period,
             const int volume_average_bars,
             const double strong_adx_level,
             const double volatility_atr_points,
             const double high_volume_multiplier,
             CLogger &logger)
   {
      Release();

      m_symbol_count = market_data.SymbolCount();
      m_timeframe = timeframe;
      m_fast_ema_period = fast_ema_period;
      m_slow_ema_period = slow_ema_period;
      m_atr_period = atr_period;
      m_adx_period = adx_period;
      m_volume_average_bars = volume_average_bars;
      m_strong_adx_level = strong_adx_level;
      m_volatility_atr_points = volatility_atr_points;
      m_high_volume_multiplier = high_volume_multiplier;

      ArrayResize(m_symbols, m_symbol_count);
      ArrayResize(m_fast_ema_handles, m_symbol_count);
      ArrayResize(m_slow_ema_handles, m_symbol_count);
      ArrayResize(m_atr_handles, m_symbol_count);
      ArrayResize(m_adx_handles, m_symbol_count);
      ArrayResize(m_volume_handles, m_symbol_count);

      for(int index = 0; index < m_symbol_count; index++)
      {
         m_fast_ema_handles[index] = INVALID_HANDLE;
         m_slow_ema_handles[index] = INVALID_HANDLE;
         m_atr_handles[index] = INVALID_HANDLE;
         m_adx_handles[index] = INVALID_HANDLE;
         m_volume_handles[index] = INVALID_HANDLE;
      }

      for(int index = 0; index < m_symbol_count; index++)
      {
         const string symbol = market_data.SymbolAt(index);
         m_symbols[index] = symbol;

         ResetLastError();
         m_fast_ema_handles[index] = iMA(symbol, m_timeframe, m_fast_ema_period, 0, MODE_EMA, PRICE_CLOSE);
         if(!CreateHandle(m_fast_ema_handles[index], symbol, "Fast EMA", logger))
         {
            Release();
            return false;
         }

         ResetLastError();
         m_slow_ema_handles[index] = iMA(symbol, m_timeframe, m_slow_ema_period, 0, MODE_EMA, PRICE_CLOSE);
         if(!CreateHandle(m_slow_ema_handles[index], symbol, "Slow EMA", logger))
         {
            Release();
            return false;
         }

         ResetLastError();
         m_atr_handles[index] = iATR(symbol, m_timeframe, m_atr_period);
         if(!CreateHandle(m_atr_handles[index], symbol, "ATR", logger))
         {
            Release();
            return false;
         }

         ResetLastError();
         m_adx_handles[index] = iADX(symbol, m_timeframe, m_adx_period);
         if(!CreateHandle(m_adx_handles[index], symbol, "ADX", logger))
         {
            Release();
            return false;
         }

         ResetLastError();
         m_volume_handles[index] = iVolumes(symbol, m_timeframe, VOLUME_TICK);
         if(!CreateHandle(m_volume_handles[index], symbol, "Tick Volume", logger))
         {
            Release();
            return false;
         }
      }

      logger.Info(StringFormat("Indicator engine initialized for %d symbol(s).", m_symbol_count));
      return true;
   }

   void Release()
   {
      for(int index = 0; index < m_symbol_count; index++)
      {
         if(m_fast_ema_handles[index] != INVALID_HANDLE)
            IndicatorRelease(m_fast_ema_handles[index]);
         if(m_slow_ema_handles[index] != INVALID_HANDLE)
            IndicatorRelease(m_slow_ema_handles[index]);
         if(m_atr_handles[index] != INVALID_HANDLE)
            IndicatorRelease(m_atr_handles[index]);
         if(m_adx_handles[index] != INVALID_HANDLE)
            IndicatorRelease(m_adx_handles[index]);
         if(m_volume_handles[index] != INVALID_HANDLE)
            IndicatorRelease(m_volume_handles[index]);
      }

      ArrayResize(m_symbols, 0);
      ArrayResize(m_fast_ema_handles, 0);
      ArrayResize(m_slow_ema_handles, 0);
      ArrayResize(m_atr_handles, 0);
      ArrayResize(m_adx_handles, 0);
      ArrayResize(m_volume_handles, 0);
      m_symbol_count = 0;
   }

   double GetFastEMA(const string symbol = "", const int shift = 0)
   {
      return IndicatorValueForSymbol(symbol == "" ? _Symbol : symbol, m_fast_ema_handles, 0, shift);
   }

   double GetSlowEMA(const string symbol = "", const int shift = 0)
   {
      return IndicatorValueForSymbol(symbol == "" ? _Symbol : symbol, m_slow_ema_handles, 0, shift);
   }

   double GetATR(const string symbol = "", const int shift = 0)
   {
      return IndicatorValueForSymbol(symbol == "" ? _Symbol : symbol, m_atr_handles, 0, shift);
   }

   double GetADX(const string symbol = "", const int shift = 0)
   {
      return IndicatorValueForSymbol(symbol == "" ? _Symbol : symbol, m_adx_handles, 0, shift);
   }

   double GetPlusDI(const string symbol = "", const int shift = 0)
   {
      return IndicatorValueForSymbol(symbol == "" ? _Symbol : symbol, m_adx_handles, 1, shift);
   }

   double GetMinusDI(const string symbol = "", const int shift = 0)
   {
      return IndicatorValueForSymbol(symbol == "" ? _Symbol : symbol, m_adx_handles, 2, shift);
   }

   long GetCurrentVolume(const string symbol = "")
   {
      return VolumeForSymbol(symbol == "" ? _Symbol : symbol, 0);
   }

   double GetAverageVolume(const int bars, const string symbol = "")
   {
      const string target_symbol = symbol == "" ? _Symbol : symbol;
      const int lookback = bars > 0 ? bars : m_volume_average_bars;
      if(lookback <= 0)
         return 0.0;

      const int symbol_index = FindSymbolIndex(target_symbol);
      if(symbol_index < 0 || m_volume_handles[symbol_index] == INVALID_HANDLE)
         return 0.0;

      double volumes[];
      ArraySetAsSeries(volumes, true);
      const int copied = CopyBuffer(m_volume_handles[symbol_index], 0, 1, lookback, volumes);
      if(copied <= 0)
         return 0.0;

      double total_volume = 0.0;
      for(int index = 0; index < copied; index++)
         total_volume += volumes[index];

      return total_volume / copied;
   }

   bool TrendIsBullish(const string symbol = "")
   {
      return GetFastEMA(symbol) > GetSlowEMA(symbol) && GetPlusDI(symbol) > GetMinusDI(symbol);
   }

   bool TrendIsBearish(const string symbol = "")
   {
      return GetFastEMA(symbol) < GetSlowEMA(symbol) && GetMinusDI(symbol) > GetPlusDI(symbol);
   }

   bool TrendStrengthStrong(const string symbol = "")
   {
      return GetADX(symbol) >= m_strong_adx_level;
   }

   bool MarketIsVolatile(const string symbol = "")
   {
      const string target_symbol = symbol == "" ? _Symbol : symbol;
      const double point = SymbolInfoDouble(target_symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return false;

      return GetATR(target_symbol) / point >= m_volatility_atr_points;
   }

   bool VolumeIsHigh(const string symbol = "")
   {
      const long current_volume = GetCurrentVolume(symbol);
      const double average_volume = GetAverageVolume(m_volume_average_bars, symbol);
      return average_volume > 0.0 && (double)current_volume >= average_volume * m_high_volume_multiplier;
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

      string text = "ApexScalperPro v0.2\n";
      text += StringFormat("Trading: %s\n", trade_engine.TradingEnabled() ? "enabled" : "disabled");
      text += StringFormat("Symbols: %d\n", market_data.SymbolCount());
      text += StringFormat("Timeframe: %s\n", EnumToString(InpTimeframe));
      text += "Status: indicator engine initialized";
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
CIndicatorEngine   g_indicator_engine;
CDashboard         g_dashboard;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_logger.Init(InpLogPrefix, InpEnableLogging);
   g_logger.Info("Initializing ApexScalperPro Version 0.2.");

   if(!g_market_data.Init(InpSymbols, _Symbol, g_logger))
      return INIT_FAILED;

   g_risk_manager.Init(InpMaxSpreadPoints, InpFixedLot);

   if(!g_indicator_engine.Init(g_market_data, InpTimeframe, InpFastEMAPeriod, InpSlowEMAPeriod, InpATRPeriod, InpADXPeriod,
                               InpVolumeAverageBars, InpStrongADXLevel, InpVolatilityATRPoints, InpHighVolumeMultiplier, g_logger))
      return INIT_FAILED;

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
   g_indicator_engine.Release();
   g_dashboard.Clear();
   g_logger.Info(StringFormat("ApexScalperPro deinitialized. Reason=%d", reason));
}


//+------------------------------------------------------------------+
//| Global indicator accessors                                       |
//+------------------------------------------------------------------+
double GetFastEMA()
{
   return g_indicator_engine.GetFastEMA();
}

double GetSlowEMA()
{
   return g_indicator_engine.GetSlowEMA();
}

double GetATR()
{
   return g_indicator_engine.GetATR();
}

double GetADX()
{
   return g_indicator_engine.GetADX();
}

double GetPlusDI()
{
   return g_indicator_engine.GetPlusDI();
}

double GetMinusDI()
{
   return g_indicator_engine.GetMinusDI();
}

long GetCurrentVolume()
{
   return g_indicator_engine.GetCurrentVolume();
}

double GetAverageVolume(int bars)
{
   return g_indicator_engine.GetAverageVolume(bars);
}

bool TrendIsBullish()
{
   return g_indicator_engine.TrendIsBullish();
}

bool TrendIsBearish()
{
   return g_indicator_engine.TrendIsBearish();
}

bool TrendStrengthStrong()
{
   return g_indicator_engine.TrendStrengthStrong();
}

bool MarketIsVolatile()
{
   return g_indicator_engine.MarketIsVolatile();
}

bool VolumeIsHigh()
{
   return g_indicator_engine.VolumeIsHigh();
}
