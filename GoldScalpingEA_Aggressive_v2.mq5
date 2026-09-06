//+------------------------------------------------------------------+
//|                  Gold Scalping EA AGGRESSIVE v2.0                |
//|              Price Action + Volume + Multiple Timeframes          |
//|                    Optimized for 3-5% Daily Profit               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://github.com/mojtaba88888/GoldScalpingEA"
#property version   "2.0"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS & STRUCTURES                                               |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE {
   SIGNAL_BUY = 1,
   SIGNAL_SELL = -1,
   SIGNAL_NONE = 0
};

struct SignalData {
   ENUM_SIGNAL_TYPE type;
   double strength;
   string reason;
   datetime time;
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - AGGRESSIVE                                    |
//+------------------------------------------------------------------+
input group "=== AGGRESSIVE TRADING ==="
input double LotSize = 0.5;                          // Lot Size (AGGRESSIVE)
input double TakeProfitPips = 25;                    // Take Profit (pips) - INCREASED
input double StopLossPips = 5;                       // Stop Loss (pips) - REDUCED
input double MaxDailyTarget = 300;                   // Daily Target ($) - 3-5%
input int MaxTrades = 8;                             // Max Concurrent Trades - INCREASED
input bool UsePartialTakeProfit = true;              // Partial TP at 50%
input double PartialTPPips = 12;                     // Partial TP Level

input group "=== PRICE ACTION PARAMETERS ==="
input int CandleAnalysisPeriod = 5;
input double PinBarThreshold = 0.55;                 // More aggressive
input double EngulfingThreshold = 0.75;              // More aggressive

input group "=== VOLUME PARAMETERS ==="
input int VolumeMA = 15;                             // Shorter MA
input double VolumeThreshold = 1.3;                  // Lower threshold
input bool UseVolumeFilter = true;

input group "=== MULTIPLE TIMEFRAMES ==="
input bool UseMultiTimeframe = true;                 // Use M1 + M5 + M15
input int FastTF = 1;                               // 1 minute
input int MediumTF = 5;                              // 5 minutes
input int SlowTF = 15;                               // 15 minutes

input group "=== TIME FILTER ==="
input string TradingStartTime = "07:00";
input string TradingEndTime = "23:00";
input bool UseTimeFilter = true;

input group "=== RISK MANAGEMENT ==="
input bool UseBreakEven = true;
input int BreakEvenPips = 3;
input bool UseTrailingStop = true;
input int TrailingStopPips = 2;
input bool UseMaxDailyLoss = true;
input double MaxDailyLoss = 150;                     // Stop if lose $150

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

datetime lastTradeTime = 0;
double dailyProfit = 0;
double dailyLoss = 0;
datetime sessionStart;
int tradeCount = 0;

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(20240906);
   trade.SetDeviationInPoints(15);
   trade.SetAsyncMode(false);
   
   sessionStart = iTime(_Symbol, PERIOD_D1, 0);
   
   Print("=== AGGRESSIVE Gold Scalping EA v2.0 Initialized ===");
   Print("Symbol: ", _Symbol);
   Print("Daily Target: $", MaxDailyTarget);
   Print("Max Trades: ", MaxTrades);
   Print("TP: ", TakeProfitPips, " pips | SL: ", StopLossPips, " pips");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT TICK                                                      |
//+------------------------------------------------------------------+
void OnTick() {
   // Update daily stats
   UpdateDailyStats();
   
   // Check if we can trade
   if(!CanTrade()) return;
   
   // Get multi-timeframe signal
   SignalData signal = GetMultiTimeframeSignal();
   
   // Execute signal
   if(signal.type == SIGNAL_BUY) {
      ExecuteBuySignal(signal);
   }
   else if(signal.type == SIGNAL_SELL) {
      ExecuteSellSignal(signal);
   }
   
   // Manage open positions
   ManagePositions();
}

//+------------------------------------------------------------------+
//| CAN TRADE FUNCTION                                               |
//+------------------------------------------------------------------+
bool CanTrade() {
   // Check account
   if(AccountInfoDouble(ACCOUNT_EQUITY) <= 0) return false;
   
   // Check daily loss
   if(UseMaxDailyLoss && dailyLoss >= MaxDailyLoss) {
      Print("❌ Daily loss limit reached: $", dailyLoss);
      return false;
   }
   
   // Check daily profit target
   if(dailyProfit >= MaxDailyTarget) {
      Print("✅ Daily target reached: $", dailyProfit);
      return false;
   }
   
   // Check max trades
   if(CountOpenTrades() >= MaxTrades) return false;
   
   // Check time filter
   if(UseTimeFilter && !IsInTradingHours()) return false;
   
   // Minimum time between trades
   if(GetTickCount() - (int)lastTradeTime < 100) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| MULTI-TIMEFRAME SIGNAL                                           |
//+------------------------------------------------------------------+
SignalData GetMultiTimeframeSignal() {
   SignalData signal;
   signal.type = SIGNAL_NONE;
   signal.strength = 0;
   signal.reason = "";
   signal.time = TimeCurrent();
   
   // Check new bar on M1
   if(iTime(_Symbol, PERIOD_M1, 0) == lastTradeTime) return signal;
   
   // Get signals from different timeframes
   SignalData fast = GetSignalOnTimeframe(PERIOD_M1);
   SignalData medium = GetSignalOnTimeframe(PERIOD_M5);
   SignalData slow = GetSignalOnTimeframe(PERIOD_M15);
   
   // Multi-timeframe confirmation
   if(UseMultiTimeframe) {
      // All timeframes agree
      if(fast.type == medium.type && medium.type == slow.type && fast.type != SIGNAL_NONE) {
         signal.type = fast.type;
         signal.strength = 0.98;
         signal.reason = "Multi-TF Alignment (M1+M5+M15)";
      }
      // Fast + Medium agree
      else if(fast.type == medium.type && fast.type != SIGNAL_NONE) {
         signal.type = fast.type;
         signal.strength = 0.90;
         signal.reason = "M1+M5 Confirmation";
      }
      // Just fast signal (aggressive)
      else if(fast.type != SIGNAL_NONE) {
         signal.type = fast.type;
         signal.strength = 0.75;
         signal.reason = "M1 Signal (Aggressive)";
      }
   }
   else {
      signal = GetSignalOnTimeframe(PERIOD_M5);
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| GET SIGNAL ON TIMEFRAME                                          |
//+------------------------------------------------------------------+
SignalData GetSignalOnTimeframe(ENUM_TIMEFRAMES tf) {
   SignalData signal;
   signal.type = SIGNAL_NONE;
   signal.strength = 0;
   signal.reason = "";
   
   // Get candle data
   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   CopyOpen(_Symbol, tf, 0, CandleAnalysisPeriod, open);
   CopyHigh(_Symbol, tf, 0, CandleAnalysisPeriod, high);
   CopyLow(_Symbol, tf, 0, CandleAnalysisPeriod, low);
   CopyClose(_Symbol, tf, 0, CandleAnalysisPeriod, close);
   
   double currOpen = open[0];
   double currHigh = high[0];
   double currLow = low[0];
   double currClose = close[0];
   
   double prevOpen = open[1];
   double prevHigh = high[1];
   double prevLow = low[1];
   double prevClose = close[1];
   
   // Check volume
   double volumes[];
   ArraySetAsSeries(volumes, true);
   CopyRealVolume(_Symbol, tf, 0, VolumeMA + 1, volumes);
   
   double avgVol = 0;
   for(int i = 1; i <= VolumeMA; i++) {
      avgVol += volumes[i];
   }
   avgVol /= VolumeMA;
   
   bool volOk = volumes[0] > avgVol * VolumeThreshold;
   
   // Detect patterns
   double bodySize = MathAbs(currClose - currOpen);
   double totalSize = currHigh - currLow;
   double lowerWick = currOpen > currClose ? currClose - currLow : currOpen - currLow;
   double upperWick = currOpen > currClose ? currHigh - currOpen : currHigh - currClose;
   
   // Pin Bar Buy
   if(totalSize > 0 && (lowerWick / totalSize) > PinBarThreshold && 
      (bodySize / totalSize) < (1 - PinBarThreshold) && lowerWick > upperWick && volOk) {
      signal.type = SIGNAL_BUY;
      signal.strength = 0.95;
      signal.reason = "Pin Bar Buy";
   }
   
   // Pin Bar Sell
   if(totalSize > 0 && (upperWick / totalSize) > PinBarThreshold && 
      (bodySize / totalSize) < (1 - PinBarThreshold) && upperWick > lowerWick && volOk) {
      signal.type = SIGNAL_SELL;
      signal.strength = 0.95;
      signal.reason = "Pin Bar Sell";
   }
   
   // Engulfing Buy
   if(currClose > prevOpen && currOpen < prevClose && currOpen < prevLow && volOk) {
      double ratio = (currClose - currOpen) / (prevClose - prevOpen);
      if(ratio > EngulfingThreshold) {
         signal.type = SIGNAL_BUY;
         signal.strength = 0.90;
         signal.reason = "Engulfing Buy";
      }
   }
   
   // Engulfing Sell
   if(currClose < prevOpen && currOpen > prevClose && currOpen > prevHigh && volOk) {
      double ratio = (currOpen - currClose) / (prevOpen - prevClose);
      if(ratio > EngulfingThreshold) {
         signal.type = SIGNAL_SELL;
         signal.strength = 0.90;
         signal.reason = "Engulfing Sell";
      }
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| EXECUTE BUY SIGNAL                                               |
//+------------------------------------------------------------------+
void ExecuteBuySignal(SignalData &signal) {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = ask - (StopLossPips * _Point);
   double takeProfit = ask + (TakeProfitPips * _Point);
   
   stopLoss = NormalizePrice(stopLoss);
   takeProfit = NormalizePrice(takeProfit);
   
   if(trade.Buy(LotSize, _Symbol, ask, stopLoss, takeProfit, signal.reason)) {
      Print("✅ BUY: ", signal.reason, " | Price: ", ask, " | TP: ", takeProfit, " | SL: ", stopLoss);
      lastTradeTime = GetTickCount();
      tradeCount++;
   }
}

//+------------------------------------------------------------------+
//| EXECUTE SELL SIGNAL                                              |
//+------------------------------------------------------------------+
void ExecuteSellSignal(SignalData &signal) {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = bid + (StopLossPips * _Point);
   double takeProfit = bid - (TakeProfitPips * _Point);
   
   stopLoss = NormalizePrice(stopLoss);
   takeProfit = NormalizePrice(takeProfit);
   
   if(trade.Sell(LotSize, _Symbol, bid, stopLoss, takeProfit, signal.reason)) {
      Print("✅ SELL: ", signal.reason, " | Price: ", bid, " | TP: ", takeProfit, " | SL: ", stopLoss);
      lastTradeTime = GetTickCount();
      tradeCount++;
   }
}

//+------------------------------------------------------------------+
//| MANAGE POSITIONS                                                 |
//+------------------------------------------------------------------+
void ManagePositions() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!positionInfo.SelectByIndex(i)) continue;
      
      if(positionInfo.Symbol() != _Symbol) continue;
      if(positionInfo.Magic() != trade.GetMagicNumber()) continue;
      
      ulong ticket = positionInfo.Ticket();
      ENUM_POSITION_TYPE posType = positionInfo.PositionType();
      double posVolume = positionInfo.Volume();
      double posOpenPrice = positionInfo.PriceOpen();
      double posSL = positionInfo.StopLoss();
      double posTP = positionInfo.TakeProfit();
      
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // Partial Take Profit
      if(UsePartialTakeProfit && posVolume == LotSize) {
         if(posType == POSITION_TYPE_BUY && ask >= posOpenPrice + (PartialTPPips * _Point)) {
            // Close 50%
            if(trade.PositionClosePartial(ticket, LotSize / 2)) {
               Print("📊 Partial TP: Closed 50% at ", ask);
            }
         }
         if(posType == POSITION_TYPE_SELL && bid <= posOpenPrice - (PartialTPPips * _Point)) {
            if(trade.PositionClosePartial(ticket, LotSize / 2)) {
               Print("📊 Partial TP: Closed 50% at ", bid);
            }
         }
      }
      
      // Break Even
      if(UseBreakEven) {
         if(posType == POSITION_TYPE_BUY && bid > posOpenPrice + (BreakEvenPips * _Point)) {
            if(posSL < posOpenPrice) {
               double newSL = NormalizePrice(posOpenPrice + 1 * _Point);
               trade.PositionModify(ticket, newSL, posTP);
            }
         }
         if(posType == POSITION_TYPE_SELL && bid < posOpenPrice - (BreakEvenPips * _Point)) {
            if(posSL > posOpenPrice) {
               double newSL = NormalizePrice(posOpenPrice - 1 * _Point);
               trade.PositionModify(ticket, newSL, posTP);
            }
         }
      }
      
      // Trailing Stop
      if(UseTrailingStop) {
         if(posType == POSITION_TYPE_BUY && bid > posSL + (TrailingStopPips * _Point)) {
            double newSL = NormalizePrice(bid - (TrailingStopPips * _Point));
            if(newSL > posSL) {
               trade.PositionModify(ticket, newSL, posTP);
            }
         }
         if(posType == POSITION_TYPE_SELL && bid < posSL - (TrailingStopPips * _Point)) {
            double newSL = NormalizePrice(bid + (TrailingStopPips * _Point));
            if(newSL < posSL) {
               trade.PositionModify(ticket, newSL, posTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| COUNT OPEN TRADES                                                |
//+------------------------------------------------------------------+
int CountOpenTrades() {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(positionInfo.SelectByIndex(i)) {
         if(positionInfo.Symbol() == _Symbol && 
            positionInfo.Magic() == trade.GetMagicNumber()) {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| UPDATE DAILY STATS                                               |
//+------------------------------------------------------------------+
void UpdateDailyStats() {
   // Reset if new day
   if(iTime(_Symbol, PERIOD_D1, 0) != sessionStart) {
      dailyProfit = 0;
      dailyLoss = 0;
      tradeCount = 0;
      sessionStart = iTime(_Symbol, PERIOD_D1, 0);
   }
   
   // Calculate from closed positions today
   dailyProfit = 0;
   dailyLoss = 0;
   
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--) {
      if(!orderInfo.SelectByIndex(i)) continue;
      
      if(orderInfo.Symbol() == _Symbol && 
         orderInfo.Magic() == trade.GetMagicNumber() &&
         orderInfo.OrderCreateTime() >= sessionStart) {
         
         double profit = orderInfo.Profit();
         if(profit > 0) {
            dailyProfit += profit;
         } else {
            dailyLoss += MathAbs(profit);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| IS IN TRADING HOURS                                              |
//+------------------------------------------------------------------+
bool IsInTradingHours() {
   MqlDateTime now;
   TimeCurrent(now);
   
   string currentTime = StringFormat("%02d:%02d", now.hour, now.min);
   
   if(currentTime >= TradingStartTime && currentTime <= TradingEndTime) {
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| NORMALIZE PRICE                                                  |
//+------------------------------------------------------------------+
double NormalizePrice(double price) {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0) tickSize = _Point;
   
   return MathRound(price / tickSize) * tickSize;
}

//+------------------------------------------------------------------+
//| END OF EXPERT ADVISOR                                            |
//+------------------------------------------------------------------+
