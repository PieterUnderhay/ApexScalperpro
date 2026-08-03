//+------------------------------------------------------------------+
//|                                               ApexScalperPro.mq5  |
//|                      Professional MT5 Expert Advisor - Version 0.6|
//+------------------------------------------------------------------+
#property strict
#property version   "0.600"
#property description "ApexScalperPro Version 0.6 - Session-Aware Decision Engine"

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
input int    InpMinimumMarketScore       = 60;          // Minimum market quality score
input double InpRangingADXLevel          = 18.0;        // Ranging market ADX threshold
input int    InpMinimumDecisionConfidence = 70;         // Minimum confidence required for BUY or SELL
input double InpMinimumEMAGapATR          = 0.10;       // Minimum EMA separation as a fraction of ATR
input double InpMinimumDirectionalDIGap   = 3.0;        // Minimum +DI/-DI separation
input bool   InpUseSessionFilter          = true;       // Restrict decisions to configured server-time session
input int    InpSessionStartHour          = 7;          // Session start hour, server time (0..23)
input int    InpSessionEndHour            = 20;         // Session end hour, server time (0..23, end exclusive)

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

   double IndicatorValueForSymbol(const string symbol, const int &handles[], const int buffer_index, const int shift)
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

   long GetCurrentVolume(const string symbol = "", const int shift = 0)
   {
      return VolumeForSymbol(symbol == "" ? _Symbol : symbol, shift);
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

   bool TrendIsBullish(const string symbol = "", const int shift = 0)
   {
      return GetFastEMA(symbol, shift) > GetSlowEMA(symbol, shift) && GetPlusDI(symbol, shift) > GetMinusDI(symbol, shift);
   }

   bool TrendIsBearish(const string symbol = "", const int shift = 0)
   {
      return GetFastEMA(symbol, shift) < GetSlowEMA(symbol, shift) && GetMinusDI(symbol, shift) > GetPlusDI(symbol, shift);
   }

   bool TrendStrengthStrong(const string symbol = "", const int shift = 0)
   {
      return GetADX(symbol, shift) >= m_strong_adx_level;
   }

   bool MarketIsVolatile(const string symbol = "", const int shift = 0)
   {
      const string target_symbol = symbol == "" ? _Symbol : symbol;
      const double point = SymbolInfoDouble(target_symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return false;

      return GetATR(target_symbol, shift) / point >= m_volatility_atr_points;
   }

   bool VolumeIsHigh(const string symbol = "", const int shift = 0)
   {
      const long current_volume = GetCurrentVolume(symbol, shift);
      const double average_volume = GetAverageVolume(m_volume_average_bars, symbol);
      return average_volume > 0.0 && (double)current_volume >= average_volume * m_high_volume_multiplier;
   }
};


//+------------------------------------------------------------------+
//| Market scanner                                                   |
//+------------------------------------------------------------------+
enum ENUM_MARKET_TREND_DIRECTION
{
   MARKET_TREND_RANGE = 0,
   MARKET_TREND_BULLISH = 1,
   MARKET_TREND_BEARISH = -1
};

class CMarketScanner
{
private:
   string m_symbols[];
   int    m_scores[];
   ENUM_MARKET_TREND_DIRECTION m_trends[];
   double m_adx_values[];
   double m_atr_points[];
   int    m_spread_points[];
   double m_volume_ratios[];
   bool   m_tradable[];
   bool   m_ranging[];
   bool   m_high_volatility[];
   int    m_symbol_count;
   int    m_max_spread_points;
   int    m_minimum_market_score;
   int    m_volume_average_bars;
   double m_strong_adx_level;
   double m_ranging_adx_level;
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

   int ClampScore(const double value)
   {
      return (int)MathMax(0.0, MathMin(100.0, MathRound(value)));
   }

   double ComponentScore(const double value, const double target)
   {
      if(target <= 0.0)
         return 0.0;

      return MathMin(1.0, MathMax(0.0, value / target));
   }

   string TrendToText(const ENUM_MARKET_TREND_DIRECTION direction)
   {
      if(direction == MARKET_TREND_BULLISH)
         return "Bullish";
      if(direction == MARKET_TREND_BEARISH)
         return "Bearish";
      return "Range";
   }

public:
   CMarketScanner()
   {
      m_symbol_count = 0;
      m_max_spread_points = 0;
      m_minimum_market_score = 0;
      m_volume_average_bars = 0;
      m_strong_adx_level = 0.0;
      m_ranging_adx_level = 0.0;
      m_volatility_atr_points = 0.0;
      m_high_volume_multiplier = 0.0;
   }

   bool Init(CMarketDataManager &market_data,
             const int max_spread_points,
             const int minimum_market_score,
             const int volume_average_bars,
             const double strong_adx_level,
             const double ranging_adx_level,
             const double volatility_atr_points,
             const double high_volume_multiplier,
             CLogger &logger)
   {
      m_symbol_count = market_data.SymbolCount();
      m_max_spread_points = max_spread_points;
      m_minimum_market_score = minimum_market_score;
      m_volume_average_bars = volume_average_bars;
      m_strong_adx_level = strong_adx_level;
      m_ranging_adx_level = ranging_adx_level;
      m_volatility_atr_points = volatility_atr_points;
      m_high_volume_multiplier = high_volume_multiplier;

      ArrayResize(m_symbols, m_symbol_count);
      ArrayResize(m_scores, m_symbol_count);
      ArrayResize(m_trends, m_symbol_count);
      ArrayResize(m_adx_values, m_symbol_count);
      ArrayResize(m_atr_points, m_symbol_count);
      ArrayResize(m_spread_points, m_symbol_count);
      ArrayResize(m_volume_ratios, m_symbol_count);
      ArrayResize(m_tradable, m_symbol_count);
      ArrayResize(m_ranging, m_symbol_count);
      ArrayResize(m_high_volatility, m_symbol_count);

      for(int index = 0; index < m_symbol_count; index++)
      {
         m_symbols[index] = market_data.SymbolAt(index);
         m_scores[index] = 0;
         m_trends[index] = MARKET_TREND_RANGE;
         m_adx_values[index] = 0.0;
         m_atr_points[index] = 0.0;
         m_spread_points[index] = 0;
         m_volume_ratios[index] = 0.0;
         m_tradable[index] = false;
         m_ranging[index] = true;
         m_high_volatility[index] = false;
      }

      logger.Info(StringFormat("Market scanner initialized for %d symbol(s).", m_symbol_count));
      return m_symbol_count > 0;
   }

   bool ScanSymbol(const string symbol, CMarketDataManager &market_data, CIndicatorEngine &indicator_engine, CLogger &logger)
   {
      const int index …1799 tokens truncated…st string symbol)
   {
      for(int index = 0; index < m_symbol_count; index++)
      {
         if(m_symbols[index] == symbol)
            return index;
      }

      return -1;
   }

   double ClampConfidence(const double value)
   {
      return MathMax(0.0, MathMin(100.0, MathRound(value)));
   }

   string DecisionToText(const DecisionType decision)
   {
      if(decision == DECISION_BUY)
         return "BUY";
      if(decision == DECISION_SELL)
         return "SELL";
      return "NO TRADE";
   }

   void AddReason(string &reason, const string item)
   {
      if(reason != "")
         reason += "; ";
      reason += item;
   }

public:
   CDecisionEngine()
   {
      m_symbol_count = 0;
      m_max_spread_points = 0;
      m_minimum_market_score = 0;
      m_minimum_confidence = 0;
      m_minimum_ema_gap_atr = 0.0;
      m_minimum_directional_di_gap = 0.0;
   }

   bool Init(CMarketDataManager &market_data,
             const int max_spread_points,
             const int minimum_market_score,
             const int minimum_confidence,
             const double minimum_ema_gap_atr,
             const double minimum_directional_di_gap,
             CLogger &logger)
   {
      m_symbol_count = market_data.SymbolCount();
      m_max_spread_points = max_spread_points;
      m_minimum_market_score = minimum_market_score;
      m_minimum_confidence = minimum_confidence;
      m_minimum_ema_gap_atr = minimum_ema_gap_atr;
      m_minimum_directional_di_gap = minimum_directional_di_gap;

      ArrayResize(m_symbols, m_symbol_count);
      ArrayResize(m_decisions, m_symbol_count);
      ArrayResize(m_confidence, m_symbol_count);
      ArrayResize(m_reasons, m_symbol_count);

      for(int index = 0; index < m_symbol_count; index++)
      {
         m_symbols[index] = market_data.SymbolAt(index);
         m_decisions[index] = DECISION_NO_TRADE;
         m_confidence[index] = 0.0;
         m_reasons[index] = "Decision engine awaiting market scan";
      }

      logger.Info(StringFormat("Decision engine initialized for %d symbol(s).", m_symbol_count));
      return m_symbol_count > 0;
   }

   DecisionType EvaluateDecision(const string symbol, CIndicatorEngine &indicator_engine, CMarketScanner &scanner, CSessionFilter &session_filter, CLogger &logger)
   {
      const int index = FindSymbolIndex(symbol);
      if(index < 0)
         return DECISION_NO_TRADE;

      const int confirmed_shift = 1;
      const double fast_ema = indicator_engine.GetFastEMA(symbol, confirmed_shift);
      const double slow_ema = indicator_engine.GetSlowEMA(symbol, confirmed_shift);
      const double atr = indicator_engine.GetATR(symbol, confirmed_shift);
      const double plus_di = indicator_engine.GetPlusDI(symbol, confirmed_shift);
      const double minus_di = indicator_engine.GetMinusDI(symbol, confirmed_shift);
      const bool data_available = fast_ema > 0.0 && slow_ema > 0.0 && atr > 0.0;
      const bool bullish = data_available && indicator_engine.TrendIsBullish(symbol, confirmed_shift);
      const bool bearish = data_available && indicator_engine.TrendIsBearish(symbol, confirmed_shift);
      const bool strong_adx = data_available && indicator_engine.TrendStrengthStrong(symbol, confirmed_shift);
      const bool healthy_atr = data_available && !indicator_engine.MarketIsVolatile(symbol, confirmed_shift);
      const bool ema_gap_ok = data_available && MathAbs(fast_ema - slow_ema) / atr >= m_minimum_ema_gap_atr;
      const bool directional_di_gap_ok = data_available && MathAbs(plus_di - minus_di) >= m_minimum_directional_di_gap;
      const bool high_volume = indicator_engine.VolumeIsHigh(symbol, confirmed_shift);
      const bool acceptable_volume = scanner.IsTickVolumeQualityAcceptable(symbol);
      const bool acceptable_spread = scanner.IsSpreadQualityAcceptable(symbol);
      const bool market_score_ok = scanner.GetMarketScore(symbol) >= m_minimum_market_score;
      const bool tradable_market = scanner.IsMarketTradable(symbol);
      const bool session_allowed = session_filter.IsAllowed();

      string reason = "";
      AddReason(reason, data_available ? "Closed-bar data confirmed" : "Insufficient closed-bar data");
      if(bullish)
         AddReason(reason, "Bullish EMA/DI alignment");
      else if(bearish)
         AddReason(reason, "Bearish EMA/DI alignment");
      else
         AddReason(reason, "Weak trend");

      AddReason(reason, strong_adx ? "ADX above threshold" : "ADX below threshold");
      AddReason(reason, healthy_atr ? "Healthy ATR" : "Unhealthy ATR volatility");
      AddReason(reason, ema_gap_ok ? "EMA separation confirmed" : "EMA separation too narrow");
      AddReason(reason, directional_di_gap_ok ? "DI separation confirmed" : "DI separation too narrow");
      AddReason(reason, high_volume ? "High volume" : (acceptable_volume ? "Acceptable volume" : "Low volume"));
      AddReason(reason, acceptable_spread ? "Spread acceptable" : "High spread");
      AddReason(reason, market_score_ok ? "Market quality score acceptable" : "Low market score");
      AddReason(reason, session_allowed ? "Session allowed" : "Outside trading session");

      double confidence = 0.0;
      if(bullish || bearish)
         confidence += 20.0;
      if(strong_adx)
         confidence += 20.0;
      if(healthy_atr)
         confidence += 15.0;
      if(ema_gap_ok)
         confidence += 15.0;
      if(directional_di_gap_ok)
         confidence += 10.0;
      if(high_volume)
         confidence += 10.0;
      else if(acceptable_volume)
         confidence += 5.0;
      if(acceptable_spread)
         confidence += 5.0;
      if(market_score_ok)
         confidence += 5.0;

      DecisionType decision = DECISION_NO_TRADE;
      if(data_available && tradable_market && session_allowed && strong_adx && healthy_atr && ema_gap_ok && directional_di_gap_ok && acceptable_spread && acceptable_volume && confidence >= m_minimum_confidence)
      {
         if(bullish)
            decision = DECISION_BUY;
         else if(bearish)
            decision = DECISION_SELL;
      }

      if(decision == DECISION_NO_TRADE)
         confidence = MathMin(confidence, (double)(m_minimum_confidence - 1));

      m_decisions[index] = decision;
      m_confidence[index] = ClampConfidence(confidence);
      m_reasons[index] = reason;

      logger.Info(StringFormat("%s decision: %s Confidence: %.0f%% Reason: %s", symbol, DecisionToText(decision), m_confidence[index], m_reasons[index]));

      return decision;
   }

   DecisionType EvaluateDecision(const string symbol)
   {
      const int index = FindSymbolIndex(symbol == "" ? _Symbol : symbol);
      return index >= 0 ? m_decisions[index] : DECISION_NO_TRADE;
   }

   bool ShouldBuy(const string symbol)
   {
      return EvaluateDecision(symbol) == DECISION_BUY;
   }

   bool ShouldSell(const string symbol)
   {
      return EvaluateDecision(symbol) == DECISION_SELL;
   }

   bool ShouldTrade(const string symbol)
   {
      const DecisionType decision = EvaluateDecision(symbol);
      return decision == DECISION_BUY || decision == DECISION_SELL;
   }

   double DecisionConfidence(const string symbol)
   {
      const int index = FindSymbolIndex(symbol == "" ? _Symbol : symbol);
      return index >= 0 ? m_confidence[index] : 0.0;
   }

   string DecisionReason(const string symbol)
   {
      const int index = FindSymbolIndex(symbol == "" ? _Symbol : symbol);
      return index >= 0 ? m_reasons[index] : "Decision unavailable";
   }

   string DecisionText(const string symbol)
   {
      return DecisionToText(EvaluateDecision(symbol));
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

   void Render(CMarketDataManager &market_data, CTradeEngine &trade_engine, CMarketScanner &scanner, CDecisionEngine &decision_engine)
   {
      if(!m_enabled)
         return;

      string primary_symbol = market_data.SymbolAt(0);
      string text = "ApexScalperPro Version 0.5\n";
      text += StringFormat("Trading: %s\n", trade_engine.TradingEnabled() ? "enabled" : "disabled");
      text += StringFormat("Symbols: %d\n", market_data.SymbolCount());
      text += StringFormat("Timeframe: %s\n", EnumToString(InpTimeframe));
      text += StringFormat("Market Score: %d\n", scanner.GetMarketScore(primary_symbol));
      text += StringFormat("Trend: %s (%s)\n", scanner.TrendDirection(primary_symbol), scanner.TrendStrength(primary_symbol));
      text += StringFormat("ADX: %.2f\n", scanner.GetADX(primary_symbol));
      text += StringFormat("Spread: %d points\n", scanner.GetSpreadPoints(primary_symbol));
      text += StringFormat("Volatility: %s\n", scanner.Volatility(primary_symbol));
      text += StringFormat("Decision: %s\n", decision_engine.DecisionText(primary_symbol));
      text += StringFormat("Confidence: %.0f%%\n", decision_engine.DecisionConfidence(primary_symbol));
      text += StringFormat("Reason: %s", decision_engine.DecisionReason(primary_symbol));
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
CMarketScanner     g_market_scanner;
CSessionFilter     g_session_filter;
CDecisionEngine    g_decision_engine;
CDashboard         g_dashboard;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_logger.Init(InpLogPrefix, InpEnableLogging);
   g_logger.Info("Initializing ApexScalperPro Version 0.6.");

   if(InpMinimumDecisionConfidence < 1 || InpMinimumDecisionConfidence > 100 || InpMinimumEMAGapATR < 0.0 || InpMinimumDirectionalDIGap < 0.0 || InpSessionStartHour < 0 || InpSessionStartHour > 23 || InpSessionEndHour < 0 || InpSessionEndHour > 23)
   {
      g_logger.Error("Invalid Decision Engine inputs. Check confidence, separation thresholds, and session hours.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(!g_market_data.Init(InpSymbols, _Symbol, g_logger))
      return INIT_FAILED;

   g_risk_manager.Init(InpMaxSpreadPoints, InpFixedLot);

   if(!g_indicator_engine.Init(g_market_data, InpTimeframe, InpFastEMAPeriod, InpSlowEMAPeriod, InpATRPeriod, InpADXPeriod,
                               InpVolumeAverageBars, InpStrongADXLevel, InpVolatilityATRPoints, InpHighVolumeMultiplier, g_logger))
      return INIT_FAILED;

   if(!g_market_scanner.Init(g_market_data, InpMaxSpreadPoints, InpMinimumMarketScore, InpVolumeAverageBars,
                             InpStrongADXLevel, InpRangingADXLevel, InpVolatilityATRPoints, InpHighVolumeMultiplier, g_logger))
      return INIT_FAILED;

   g_session_filter.Init(InpUseSessionFilter, InpSessionStartHour, InpSessionEndHour);
   if(!g_decision_engine.Init(g_market_data, InpMaxSpreadPoints, InpMinimumMarketScore,
                              InpMinimumDecisionConfidence, InpMinimumEMAGapATR, InpMinimumDirectionalDIGap, g_logger))
      return INIT_FAILED;

   g_trade_engine.Init(InpMagicNumber, InpDeviationPoints, InpEnableTrading);
   g_dashboard.Init(InpEnableDashboard);
   g_market_scanner.Scan(g_market_data, g_indicator_engine, g_logger);
   for(int index = 0; index < g_market_data.SymbolCount(); index++)
      g_decision_engine.EvaluateDecision(g_market_data.SymbolAt(index), g_indicator_engine, g_market_scanner, g_session_filter, g_logger);
   g_dashboard.Render(g_market_data, g_trade_engine, g_market_scanner, g_decision_engine);

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

      g_market_scanner.ScanSymbol(symbol, g_market_data, g_indicator_engine, g_logger);
      g_decision_engine.EvaluateDecision(symbol, g_indicator_engine, g_market_scanner, g_session_filter, g_logger);

      const int spread_points = g_market_data.SpreadPoints(symbol);
      if(!g_risk_manager.IsSpreadAllowed(symbol, spread_points, g_logger))
         continue;
      if(!g_market_scanner.IsMarketTradable(symbol))
         continue;

      // Version 0.4 evaluates decisions only; trade execution remains disabled until a later milestone.
      if(!g_decision_engine.ShouldTrade(symbol))
         continue;

      const double lot = g_risk_manager.LotSize(symbol);
      if(lot <= 0.0)
         g_logger.Warn(StringFormat("Calculated lot size for %s is invalid: %.2f", symbol, lot));
   }

   g_dashboard.Render(g_market_data, g_trade_engine, g_market_scanner, g_decision_engine);
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


//+------------------------------------------------------------------+
//| Global market scanner accessors                                  |
//+------------------------------------------------------------------+
bool IsMarketTradable()
{
   return g_market_scanner.IsMarketTradable();
}

int GetMarketScore()
{
   return g_market_scanner.GetMarketScore();
}

string TrendDirection()
{
   return g_market_scanner.TrendDirection();
}

string TrendStrength()
{
   return g_market_scanner.TrendStrength();
}


//+------------------------------------------------------------------+
//| Global decision engine accessors                                 |
//+------------------------------------------------------------------+
DecisionType EvaluateDecision(string symbol)
{
   return g_decision_engine.EvaluateDecision(symbol);
}

bool ShouldBuy(string symbol)
{
   return g_decision_engine.ShouldBuy(symbol);
}

bool ShouldSell(string symbol)
{
   return g_decision_engine.ShouldSell(symbol);
}

bool ShouldTrade(string symbol)
{
   return g_decision_engine.ShouldTrade(symbol);
}

double DecisionConfidence(string symbol)
{
   return g_decision_engine.DecisionConfidence(symbol);
}

string DecisionReason(string symbol)
{
   return g_decision_engine.DecisionReason(symbol);
}
