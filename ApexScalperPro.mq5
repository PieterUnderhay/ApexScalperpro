//+------------------------------------------------------------------+
//|                                               ApexScalperPro.mq5  |
//|                      Professional MT5 Expert Advisor - Version 1.0|
//+------------------------------------------------------------------+
#property strict
#property version   "1.010"
#property description "ApexScalperPro Phase 2 - Signal Quality Controls"

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
input bool   InpEnableStrategyTesterTrading = false;   // Permit entries only when running in MT5 Strategy Tester
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
input bool   InpUseDynamicLotSizing        = false;      // Use equity-risk sizing instead of fixed lots
input double InpRiskPerTradePercent        = 0.50;       // Equity risk percentage for dynamic lot sizing
input int    InpReferenceStopPoints        = 100;        // Reference stop distance for risk sizing
input int    InpMaxManagedPositions        = 1;          // Future maximum positions per symbol and magic number
input bool   InpAllowHedging                = false;      // Future permission for opposite-direction managed exposure
input bool   InpUseCandleConfirmation       = true;       // Require confirmed closed candle direction
input double InpMinimumCandleBodyATR        = 0.10;       // Minimum closed candle body as fraction of ATR
input bool   InpUseDecisionCooldown          = true;       // Suppress closely clustered qualified signals
input int    InpDecisionCooldownSeconds      = 300;        // Per-symbol qualified-signal cooldown; 0 disables
input double InpStopLossATRMultiplier        = 1.20;       // Initial stop loss distance in ATR multiples
input double InpTakeProfitATRMultiplier      = 1.80;       // Initial take profit distance in ATR multiples
input bool   InpEnableBreakEven              = true;       // Move profitable positions to break-even
input double InpBreakEvenTriggerATR          = 1.00;       // Profit required before break-even, in ATR multiples
input int    InpBreakEvenOffsetPoints        = 2;          // Protective break-even offset in points
input bool   InpEnableATRTrailing            = true;       // Apply ATR-based trailing stop
input double InpTrailingStartATR             = 1.50;       // Profit required before trailing, in ATR multiples
input double InpTrailingDistanceATR          = 1.00;       // Trailing distance in ATR multiples
input bool   InpUseMarketStructureFilter     = true;       // Require structure agreement with decision direction
input int    InpStructureLookbackBars        = 40;         // Closed bars used for swing analysis
input int    InpSwingDepthBars               = 2;          // Bars on each side required to confirm a swing
input bool   InpUseSupportResistanceFilter   = true;       // Reject entries near opposing swing level
input int    InpMinimumSRDistancePoints      = 50;         // Minimum distance to opposing support/resistance
input bool   InpUseMultiTimeframeConfirmation = true;      // Confirm local signal on a higher timeframe
input ENUM_TIMEFRAMES InpConfirmationTimeframe = PERIOD_M5; // Higher confirmation timeframe
input int    InpMinimumTrendScore            = 70;         // Minimum composite trend score

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
//| Configuration                                                     |
//+------------------------------------------------------------------+
class CConfiguration
{
public:
   bool Validate(CLogger &logger)
   {
      if(InpMinimumDecisionConfidence < 1 || InpMinimumDecisionConfidence > 100 || InpMinimumEMAGapATR < 0.0 || InpMinimumDirectionalDIGap < 0.0 || InpMinimumCandleBodyATR < 0.0 || InpDecisionCooldownSeconds < 0)
      {
         logger.Error("Invalid Decision Engine inputs.");
         return false;
      }
      if(InpSessionStartHour < 0 || InpSessionStartHour > 23 || InpSessionEndHour < 0 || InpSessionEndHour > 23)
      {
         logger.Error("Invalid session hour inputs.");
         return false;
      }
      if(InpRiskPerTradePercent <= 0.0 || InpRiskPerTradePercent > 100.0 || InpReferenceStopPoints <= 0 || InpMaxManagedPositions < 1 || InpFixedLot <= 0.0 || InpStopLossATRMultiplier <= 0.0 || InpTakeProfitATRMultiplier <= 0.0 || InpBreakEvenTriggerATR < 0.0 || InpBreakEvenOffsetPoints < 0 || InpTrailingStartATR < 0.0 || InpTrailingDistanceATR <= 0.0)
      {
         logger.Error("Invalid risk, money-management, or position inputs.");
         return false;
      }
      if(InpFastEMAPeriod <= 0 || InpSlowEMAPeriod <= InpFastEMAPeriod || InpATRPeriod <= 0 || InpADXPeriod <= 0 || InpVolumeAverageBars <= 0 || InpMaxSpreadPoints < 0 || InpStructureLookbackBars < 10 || InpSwingDepthBars < 1 || InpStructureLookbackBars <= InpSwingDepthBars * 2 + 4 || InpMinimumSRDistancePoints < 0 || InpMinimumTrendScore < 0 || InpMinimumTrendScore > 100)
      {
         logger.Error("Invalid market or indicator inputs.");
         return false;
      }
      return true;
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
      const double point = SymbolInfoDouble(…8539 tokens truncated… }
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
   bool   m_tester_only;

public:
   void Init(const ulong magic_number, const int deviation_points, const bool enabled, const bool tester_only)
   {
      m_magic_number     = magic_number;
      m_deviation_points = deviation_points;
      m_enabled          = enabled;
      m_tester_only      = tester_only;

      m_trade.SetExpertMagicNumber(m_magic_number);
      m_trade.SetDeviationInPoints(m_deviation_points);
      m_trade.SetTypeFillingBySymbol(_Symbol);
   }

   bool TradingEnabled()
   {
      return m_enabled && (!m_tester_only || (bool)MQLInfoInteger(MQL_TESTER));
   }

   bool Buy(const string symbol, const double lot, const double stop_loss, const double take_profit, const string comment, CLogger &logger)
   {
      if(!TradingEnabled())
      {
         logger.Info("Buy request ignored because Strategy Tester trading is disabled.");
         return false;
      }

      m_trade.SetTypeFillingBySymbol(symbol);
      ResetLastError();
      if(!m_trade.Buy(lot, symbol, 0.0, stop_loss, take_profit, comment))
      {
         logger.Error(StringFormat("Buy failed for %s. Retcode=%u LastError=%d", symbol, m_trade.ResultRetcode(), GetLastError()));
         return false;
      }

      logger.Info(StringFormat("Buy placed for %s, lot %.2f, SL %.5f, TP %.5f.", symbol, lot, stop_loss, take_profit));
      return true;
   }

   bool Sell(const string symbol, const double lot, const double stop_loss, const double take_profit, const string comment, CLogger &logger)
   {
      if(!TradingEnabled())
      {
         logger.Info("Sell request ignored because Strategy Tester trading is disabled.");
         return false;
      }

      m_trade.SetTypeFillingBySymbol(symbol);
      ResetLastError();
      if(!m_trade.Sell(lot, symbol, 0.0, stop_loss, take_profit, comment))
      {
         logger.Error(StringFormat("Sell failed for %s. Retcode=%u LastError=%d", symbol, m_trade.ResultRetcode(), GetLastError()));
         return false;
      }

      logger.Info(StringFormat("Sell placed for %s, lot %.2f, SL %.5f, TP %.5f.", symbol, lot, stop_loss, take_profit));
      return true;
   }

   bool ModifyPosition(const ulong ticket, const double stop_loss, const double take_profit, CLogger &logger)
   {
      if(!TradingEnabled())
         return false;
      ResetLastError();
      if(!m_trade.PositionModify(ticket, stop_loss, take_profit))
      {
         logger.Error(StringFormat("Position modification failed for %I64u. Retcode=%u LastError=%d", ticket, m_trade.ResultRetcode(), GetLastError()));
         return false;
      }
      return true;
   }
};

//+------------------------------------------------------------------+
//| Trade manager                                                     |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
   ulong  m_magic_number;
   bool   m_break_even_enabled;
   double m_break_even_trigger_atr;
   int    m_break_even_offset_points;
   bool   m_trailing_enabled;
   double m_trailing_start_atr;
   double m_trailing_distance_atr;

public:
   void Init(const ulong magic_number, const bool break_even_enabled, const double break_even_trigger_atr, const int break_even_offset_points,
             const bool trailing_enabled, const double trailing_start_atr, const double trailing_distance_atr)
   {
      m_magic_number = magic_number;
      m_break_even_enabled = break_even_enabled;
      m_break_even_trigger_atr = break_even_trigger_atr;
      m_break_even_offset_points = break_even_offset_points;
      m_trailing_enabled = trailing_enabled;
      m_trailing_start_atr = trailing_start_atr;
      m_trailing_distance_atr = trailing_distance_atr;
   }

   void Manage(const string symbol, CIndicatorEngine &indicator_engine, CTradeEngine &trade_engine, CLogger &logger)
   {
      if(!trade_engine.TradingEnabled())
         return;

      const double atr = indicator_engine.GetATR(symbol, 0);
      const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      const int stops_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      MqlTick tick;
      if(atr <= 0.0 || point <= 0.0 || !SymbolInfoTick(symbol, tick))
         return;

      for(int index = PositionsTotal() - 1; index >= 0; index--)
      {
         const ulong ticket = PositionGetTicket(index);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol || (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic_number)
            continue;

         const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         const double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         const double current_sl = PositionGetDouble(POSITION_SL);
         const double take_profit = PositionGetDouble(POSITION_TP);
         const double market_price = type == POSITION_TYPE_BUY ? tick.bid : tick.ask;
         const double profit_distance = type == POSITION_TYPE_BUY ? market_price - open_price : open_price - market_price;
         double proposed_sl = current_sl;

         if(m_break_even_enabled && profit_distance >= atr * m_break_even_trigger_atr)
         {
            const double break_even = type == POSITION_TYPE_BUY ? open_price + m_break_even_offset_points * point : open_price - m_break_even_offset_points * point;
            if((type == POSITION_TYPE_BUY && (proposed_sl == 0.0 || break_even > proposed_sl)) || (type == POSITION_TYPE_SELL && (proposed_sl == 0.0 || break_even < proposed_sl)))
               proposed_sl = break_even;
         }

         if(m_trailing_enabled && profit_distance >= atr * m_trailing_start_atr)
         {
            const double trailing_sl = type == POSITION_TYPE_BUY ? market_price - atr * m_trailing_distance_atr : market_price + atr * m_trailing_distance_atr;
            if((type == POSITION_TYPE_BUY && (proposed_sl == 0.0 || trailing_sl > proposed_sl)) || (type == POSITION_TYPE_SELL && (proposed_sl == 0.0 || trailing_sl < proposed_sl)))
               proposed_sl = trailing_sl;
         }

         if(proposed_sl == current_sl || proposed_sl == 0.0)
            continue;
         if(type == POSITION_TYPE_BUY && proposed_sl >= tick.bid - stops_level * point)
            continue;
         if(type == POSITION_TYPE_SELL && proposed_sl <= tick.ask + stops_level * point)
            continue;
         trade_engine.ModifyPosition(ticket, NormalizeDouble(proposed_sl, digits), take_profit, logger);
      }
   }
};

//+------------------------------------------------------------------+
//| Statistics                                                       |
//+------------------------------------------------------------------+
class CStatistics
{
private:
   long m_evaluations;
   long m_buy_decisions;
   long m_sell_decisions;
   long m_no_trade_decisions;

public:
   void Reset()
   {
      m_evaluations = 0;
      m_buy_decisions = 0;
      m_sell_decisions = 0;
      m_no_trade_decisions = 0;
   }

   void RecordDecision(const DecisionType decision)
   {
      m_evaluations++;
      if(decision == DECISION_BUY)
         m_buy_decisions++;
      else if(decision == DECISION_SELL)
         m_sell_decisions++;
      else
         m_no_trade_decisions++;
   }

   string DecisionSummary()
   {
      return StringFormat("Evaluations: %I64d | BUY: %I64d | SELL: %I64d | NO TRADE: %I64d", m_evaluations, m_buy_decisions, m_sell_decisions, m_no_trade_decisions);
   }
};

//+------------------------------------------------------------------+
//| Dashboard                                                        |
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

   void Render(CMarketDataManager &market_data, CTradeEngine &trade_engine, CMarketScanner &scanner, CDecisionEngine &decision_engine, CStatistics &statistics, CMarketStructureEngine &structure_engine)
   {
      if(!m_enabled)
         return;

      string primary_symbol = market_data.SymbolAt(0);
      string text = "ApexScalperPro Phase 2\n";
      text += StringFormat("Trading: %s\n", trade_engine.TradingEnabled() ? "enabled" : "disabled");
      text += StringFormat("Symbols: %d\n", market_data.SymbolCount());
      text += StringFormat("Timeframe: %s\n", EnumToString(InpTimeframe));
      text += StringFormat("Market Score: %d\n", scanner.GetMarketScore(primary_symbol));
      text += StringFormat("Trend: %s (%s)\n", scanner.TrendDirection(primary_symbol), scanner.TrendStrength(primary_symbol));
      text += StringFormat("ADX: %.2f\n", scanner.GetADX(primary_symbol));
      text += StringFormat("Spread: %d points\n", scanner.GetSpreadPoints(primary_symbol));
      text += StringFormat("Volatility: %s\n", scanner.Volatility(primary_symbol));
      double support=0.0,resistance=0.0; const ENUM_MARKET_STRUCTURE structure=structure_engine.Analyse(primary_symbol,InpTimeframe,support,resistance); const double point=SymbolInfoDouble(primary_symbol,SYMBOL_POINT), price=SymbolInfoDouble(primary_symbol,SYMBOL_BID);
      text += StringFormat("Session: %02d:00-%02d:00\n",InpSessionStartHour,InpSessionEndHour);
      text += StringFormat("Structure: %s\n",structure_engine.Text(structure));
      text += StringFormat("Support distance: %.0f | Resistance distance: %.0f points\n",point>0.0?(price-support)/point:0.0,point>0.0?(resistance-price)/point:0.0);
      text += StringFormat("Decision: %s\n", decision_engine.DecisionText(primary_symbol));
      text += StringFormat("Confidence: %.0f%%\n", decision_engine.DecisionConfidence(primary_symbol));
      text += StringFormat("Reason: %s", decision_engine.DecisionReason(primary_symbol));
      text += StringFormat("\n%s", statistics.DecisionSummary());
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
CConfiguration     g_configuration;
CMarketDataManager g_market_data;
CRiskManager       g_risk_manager;
CMoneyManagement   g_money_management;
CPositionManager   g_position_manager;
CHedgingManager    g_hedging_manager;
CTradeEngine       g_trade_engine;
CTradeManager      g_trade_manager;
CIndicatorEngine   g_indicator_engine;
CMarketScanner     g_market_scanner;
CSessionFilter     g_session_filter;
CTradeFrequencyManager g_frequency_manager;
CMarketStructureEngine g_structure_engine;
CMultiTimeframeEngine g_mtf_engine;
CDecisionEngine    g_decision_engine;
CStatistics        g_statistics;
CDashboard         g_dashboard;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_logger.Init(InpLogPrefix, InpEnableLogging);
   g_logger.Info("Initializing ApexScalperPro Version 1.0.");

   if(!g_configuration.Validate(g_logger))
      return INIT_PARAMETERS_INCORRECT;

   if(!g_market_data.Init(InpSymbols, _Symbol, g_logger))
      return INIT_FAILED;

   g_risk_manager.Init(InpMaxSpreadPoints, InpFixedLot);
   g_money_management.Init(InpUseDynamicLotSizing, InpRiskPerTradePercent, InpReferenceStopPoints, InpFixedLot);
   g_position_manager.Init(InpMagicNumber, InpMaxManagedPositions);
   g_hedging_manager.Init(InpAllowHedging);

   if(!g_indicator_engine.Init(g_market_data, InpTimeframe, InpFastEMAPeriod, InpSlowEMAPeriod, InpATRPeriod, InpADXPeriod,
                               InpVolumeAverageBars, InpStrongADXLevel, InpVolatilityATRPoints, InpHighVolumeMultiplier, g_logger))
      return INIT_FAILED;

   if(!g_market_scanner.Init(g_market_data, InpMaxSpreadPoints, InpMinimumMarketScore, InpVolumeAverageBars,
                             InpStrongADXLevel, InpRangingADXLevel, InpVolatilityATRPoints, InpHighVolumeMultiplier, g_logger))
      return INIT_FAILED;

   g_session_filter.Init(InpUseSessionFilter, InpSessionStartHour, InpSessionEndHour);
   g_frequency_manager.Init(g_market_data, InpUseDecisionCooldown, InpDecisionCooldownSeconds);
   g_structure_engine.Init(InpStructureLookbackBars, InpSwingDepthBars);
   if(!g_decision_engine.Init(g_market_data, InpMaxSpreadPoints, InpMinimumMarketScore,
                              InpMinimumDecisionConfidence, InpMinimumEMAGapATR, InpMinimumDirectionalDIGap,
                              InpUseCandleConfirmation, InpMinimumCandleBodyATR, g_logger))
      return INIT_FAILED;

   g_trade_engine.Init(InpMagicNumber, InpDeviationPoints, InpEnableTrading, InpEnableStrategyTesterTrading);
   g_trade_manager.Init(InpMagicNumber, InpEnableBreakEven, InpBreakEvenTriggerATR, InpBreakEvenOffsetPoints,
                        InpEnableATRTrailing, InpTrailingStartATR, InpTrailingDistanceATR);
   g_statistics.Reset();
   g_dashboard.Init(InpEnableDashboard);
   g_market_scanner.Scan(g_market_data, g_indicator_engine, g_logger);
   for(int index = 0; index < g_market_data.SymbolCount(); index++)
      g_statistics.RecordDecision(g_decision_engine.EvaluateDecision(g_market_data.SymbolAt(index), g_indicator_engine, g_market_scanner, g_session_filter, g_frequency_manager, g_structure_engine, g_mtf_engine, g_logger));
   g_dashboard.Render(g_market_data, g_trade_engine, g_market_scanner, g_decision_engine, g_statistics, g_structure_engine);

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

      g_trade_manager.Manage(symbol, g_indicator_engine, g_trade_engine, g_logger);
      g_market_scanner.ScanSymbol(symbol, g_market_data, g_indicator_engine, g_logger);
      g_statistics.RecordDecision(g_decision_engine.EvaluateDecision(symbol, g_indicator_engine, g_market_scanner, g_session_filter, g_frequency_manager, g_structure_engine, g_mtf_engine, g_logger));

      const int spread_points = g_market_data.SpreadPoints(symbol);
      if(!g_risk_manager.IsSpreadAllowed(symbol, spread_points, g_logger))
         continue;
      if(!g_market_scanner.IsMarketTradable(symbol))
         continue;

      if(!g_decision_engine.ShouldTrade(symbol))
         continue;
      const DecisionType decision = g_decision_engine.EvaluateDecision(symbol);
      const ENUM_POSITION_TYPE direction = decision == DECISION_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      if(g_position_manager.HasDirection(symbol, direction) || !g_position_manager.CanOpenPosition(symbol) || !g_hedging_manager.CanOpenDirection(symbol, decision, g_position_manager))
         continue;

      const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      const int stops_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      const double atr = g_indicator_engine.GetATR(symbol, 1);
      if(point <= 0.0 || atr <= 0.0)
         continue;
      const double stop_distance = MathMax(atr * InpStopLossATRMultiplier, (stops_level + 1) * point);
      const double take_profit_distance = MathMax(atr * InpTakeProfitATRMultiplier, (stops_level + 1) * point);
      const int stop_points = (int)MathCeil(stop_distance / point);
      const double lot = g_risk_manager.NormalizeLot(symbol, g_money_management.CalculateLot(symbol, stop_points));
      if(lot <= 0.0)
      {
         g_logger.Warn(StringFormat("Calculated lot size for %s is invalid: %.2f", symbol, lot));
         continue;
      }

      if(decision == DECISION_BUY)
         g_trade_engine.Buy(symbol, lot, NormalizeDouble(tick.ask - stop_distance, digits), NormalizeDouble(tick.ask + take_profit_distance, digits), "ApexScalperPro ST Buy", g_logger);
      else if(decision == DECISION_SELL)
         g_trade_engine.Sell(symbol, lot, NormalizeDouble(tick.bid + stop_distance, digits), NormalizeDouble(tick.bid - take_profit_distance, digits), "ApexScalperPro ST Sell", g_logger);
   }

   g_dashboard.Render(g_market_data, g_trade_engine, g_market_scanner, g_decision_engine, g_statistics, g_structure_engine);
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
