//+------------------------------------------------------------------+
//|                  Gold Scalping EA AGGRESSIVE v3.0                |
//|              Price Action + Volume + Multiple Timeframes          |
//|                    FIXED & OPTIMIZED v3.0                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://github.com/mojtaba88888/GoldScalpingEA"
#property version   "3.0"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - AGGRESSIVE OPTIMIZED                          |
//+------------------------------------------------------------------+
input group "=== AGGRESSIVE TRADING ==="
input double LotSize = 0.8;                          // Lot Size (INCREASED from 0.5)
input double TakeProfitPips = 30;                    // Take Profit (INCREASED from 25)
input double StopLossPips = 4;                       // Stop Loss (DECREASED from 5)
input int MaxTrades = 12;                            // Max Concurrent Trades (INCREASED)
input bool UsePartialTakeProfit = true;              // Partial TP at 50%
input double PartialTPPips = 15;                     // Partial TP Level (INCREASED)

input group "=== PRICE ACTION PARAMETERS ==="
input int CandleAnalysisPeriod = 5;
input double PinBarThreshold = 0.50;                 // More aggressive (DECREASED)
input double EngulfingThreshold = 0.70;              // More aggressive (DECREASED)

input group "=== VOLUME PARAMETERS ==="
input int VolumeMA = 10;                             // Shorter MA (DECREASED)
input double VolumeThreshold = 1.2;                  // Lower threshold (DECREASED)
input bool UseVolumeFilter = true;

input group "=== MULTIPLE TIMEFRAMES ==="
input bool UseMultiTimeframe = true;
input ENUM_TIMEFRAMES FastTF = PERIOD_M1;
input ENUM_TIMEFRAMES MediumTF = PERIOD_M5;
input ENUM_TIMEFRAMES SlowTF = PERIOD_M15;

input group "=== TIME FILTER ==="
input bool UseTimeFilter = false;                    // DISABLED for more trading
input string TradingStartTime = "01:00";
input string TradingEndTime = "23:00";

input group "=== RISK MANAGEMENT ==="
input bool UseBreakEven = true;
input int BreakEvenPips = 2;
input bool UseTrailingStop = true;
input int TrailingStopPips = 1;
input bool UseMaxDailyLoss = true;
input double MaxDailyLoss = 100;                     // Stop if lose $100
input double MaxDailyProfit = 500;                   // Target $500/day (5%)

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
   trade.SetDeviationInPoints(20);
   trade.SetAsyncMode(false);
   
   sessionStart = iTime(_Symbol, PERIOD_D1, 0);
   
   Print("=== AGGRESSIVE Gold Scalping EA v3.0 ===");
   Print("Symbol: ", _Symbol);
   Print("Lot Size: ", LotSize);
   Print("TP: ", TakeProfitPips, " pips | SL: ", StopLossPips, " pips");
   Print("Daily Target: $", MaxDailyProfit);
   Print("Max Trades: ", MaxTrades);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT TICK                                                      |
//+------------------------------------------------------------------+
void OnTick() {
   UpdateDailyStats();
   
   if(!CanTrade()) return;
   
   SignalData signal = GetMultiTimeframeSignal();
   
   if(signal.type == SIGNAL_BUY) {
      ExecuteBuySignal(signal);
   }
   else if(signal.type == SIGNAL_SELL) {
      ExecuteSellSignal(signal);
   }
   
   ManagePositions();
}

//+------------------------------------------------------------------+
//| SIGNAL DATA STRUCTURE                                            |
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
};

//+------------------------------------------------------------------+
//| CAN TRADE FUNCTION                                               |
//+------------------------------------------------------------------+
bool CanTrade() {
   if(AccountInfoDouble(ACCOUNT_EQUITY) <= 0) return false;
   
   if(UseMaxDailyLoss && dailyLoss >= MaxDailyLoss) {
      return false;
   }
   
   if(dailyProfit >= MaxDailyProfit) {
      return false;
   }
   
   if(CountOpenTrades() >= MaxTrades) return false;
   
   if(UseTimeFilter && !IsInTradingHours()) return false;
   
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
   
   SignalData fast = GetSignalOnTimeframe(FastTF);
   SignalData medium = GetSignalOnTimeframe(MediumTF);
   SignalData slow = GetSignalOnTimeframe(SlowTF);
   
   if(UseMultiTimeframe) {
      if(fast.type == medium.type && medium.type == slow.type && fast.type != SIGNAL_NONE) {
         signal.type = fast.type;
         signal.strength = 0.98;
         signal.reason = "Alignment";
      }
      else if(fast.type == medium.type && fast.type != SIGNAL_NONE) {
         signal.type = fast.type;
         signal.strength = 0.90;
         signal.reason = "M1+M5";
      }
      else if(fast.type != SIGNAL_NONE) {
         signal.type = fast.type;
         signal.strength = 0.80;
         signal.reason = "M1";
      }
   }
   else {
      signal = GetSignalOnTimeframe(MediumTF);
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
   
   double open[];
   double high[];
   double low[];
   double close[];
   double volumes[];
   
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(volumes, true);
   
   int copied = CopyOpen(_Symbol, tf, 0, CandleAnalysisPeriod, open);
   if(copied <= 1) return signal;
   
   CopyHigh(_Symbol, tf, 0, CandleAnalysisPeriod, high);
   CopyLow(_Symbol, tf, 0, CandleAnalysisPeriod, low);
   CopyClose(_Symbol, tf, 0, CandleAnalysisPeriod, close);
   CopyRealVolume(_Symbol, tf, 0, VolumeMA + 1, volumes);
   
   double currOpen = open[0];
   double currHigh = high[0];
   double currLow = low[0];
   double currClose = close[0];
   
   double prevOpen = open[1];
   double prevHigh = high[1];
   double prevLow = low[1];
   double prevClose = close[1];
   
   double avgVol = 0;
   int volCount = (VolumeMA < ArraySize(volumes) - 1) ? VolumeMA : ArraySize(volumes) - 2;
   
   if(volCount > 0) {
      for(int i = 1; i <= volCount; i++) {
         if(volumes[i] > 0) avgVol += volumes[i];
      }
      avgVol /= volCount;
   }
   
   bool volOk = (avgVol > 0) ? (volumes[0] > avgVol * VolumeThreshold) : true;
   
   double bodySize = MathAbs(currClose - currOpen);
   double totalSize = currHigh - currLow;
   
   if(totalSize > 0) {
      double lowerWick = (currOpen > currClose) ? (currClose - currLow) : (currOpen - currLow);
      double upperWick = (currOpen > currClose) ? (currHigh - currOpen) : (currHigh - currClose);
      
      if((lowerWick / totalSize) > PinBarThreshold && (bodySize / totalSize) < (1.0 - PinBarThreshold)) {
         if(lowerWick > upperWick && volOk) {
            signal.type = SIGNAL_BUY;
            signal.strength = 0.95;
         }
      }
      
      if((upperWick / totalSize) > PinBarThreshold && (bodySize / totalSize) < (1.0 - PinBarThreshold)) {
         if(upperWick > lowerWick && volOk) {
            signal.type = SIGNAL_SELL;
            signal.strength = 0.95;
         }
      }
   }
   
   if(signal.type == SIGNAL_NONE) {
      double prevBody = MathAbs(prevClose - prevOpen);
      
      if(prevBody > 0) {
         double currBody = MathAbs(currClose - currOpen);
         
         if(currClose > prevOpen && currOpen < prevClose && currOpen < prevLow && volOk) {
            if(currBody > prevBody * EngulfingThreshold) {
               signal.type = SIGNAL_BUY;
               signal.strength = 0.90;
            }
         }
         
         if(currClose < prevOpen && currOpen > prevClose && currOpen > prevHigh && volOk) {
            if(currBody > prevBody * EngulfingThreshold) {
               signal.type = SIGNAL_SELL;
               signal.strength = 0.90;
            }
         }
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
   
   if(trade.Buy(LotSize, _Symbol, ask, stopLoss, takeProfit)) {
      Print("BUY: ", signal.reason, " Price: ", ask);
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
   
   if(trade.Sell(LotSize, _Symbol, bid, stopLoss, takeProfit)) {
      Print("SELL: ", signal.reason, " Price: ", bid);
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
      if(positionInfo.Magic() != 20240906) continue;
      
      ulong ticket = positionInfo.Ticket();
      ENUM_POSITION_TYPE posType = positionInfo.PositionType();
      double posVolume = positionInfo.Volume();
      double posOpenPrice = positionInfo.PriceOpen();
      double posSL = positionInfo.StopLoss();
      double posTP = positionInfo.TakeProfit();
      
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      if(UsePartialTakeProfit && posVolume == LotSize) {
         if(posType == POSITION_TYPE_BUY && ask >= posOpenPrice + (PartialTPPips * _Point)) {
            if(trade.PositionClosePartial(ticket, LotSize / 2)) {
               Print("Partial TP: ", ask);
            }
         }
         if(posType == POSITION_TYPE_SELL && bid <= posOpenPrice - (PartialTPPips * _Point)) {
            if(trade.PositionClosePartial(ticket, LotSize / 2)) {
               Print("Partial TP: ", bid);
            }
         }
      }
      
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
            positionInfo.Magic() == 20240906) {
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
   if(iTime(_Symbol, PERIOD_D1, 0) != sessionStart) {
      dailyProfit = 0;
      dailyLoss = 0;
      tradeCount = 0;
      sessionStart = iTime(_Symbol, PERIOD_D1, 0);
   }
   
   dailyProfit = 0;
   dailyLoss = 0;
   
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--) {
      if(!orderInfo.SelectByIndex(i)) continue;
      
      if(orderInfo.Symbol() == _Symbol && 
         orderInfo.Magic() == 20240906 &&
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
