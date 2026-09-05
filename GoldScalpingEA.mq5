//+------------------------------------------------------------------+
//|                     Gold Scalping EA v1.0                        |
//|                  Price Action + Volume Strategy                  |
//|                    Optimized for MetaTrader 5                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://github.com/mojtaba88888/GoldScalpingEA"
#property version   "1.0"
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
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== TRADING PARAMETERS ==="
input double LotSize = 0.1;                          // Lot Size
input double TakeProfitPips = 15;                    // Take Profit (pips)
input double StopLossPips = 8;                       // Stop Loss (pips)
input double MaxDailyLoss = 100;                     // Max Daily Loss ($)
input int MaxTrades = 3;                             // Max Concurrent Trades

input group "=== PRICE ACTION PARAMETERS ==="
input int CandleAnalysisPeriod = 5;                  // Candle Analysis Period
input double PinBarThreshold = 0.6;                  // Pin Bar Threshold (0.0-1.0)
input double EngulfingThreshold = 0.8;               // Engulfing Threshold (0.0-1.0)

input group "=== VOLUME PARAMETERS ==="
input int VolumeMA = 20;                             // Volume MA Period
input double VolumeThreshold = 1.5;                  // Volume Threshold Multiplier
input bool UseVolumeFilter = true;                   // Use Volume Filter

input group "=== TIME FILTER ==="
input string TradingStartTime = "08:00";             // Trading Start Time (HH:MM)
input string TradingEndTime = "22:00";               // Trading End Time (HH:MM)
input bool UseTimeFilter = true;                     // Use Time Filter

input group "=== RISK MANAGEMENT ==="
input bool UseBreakEven = true;                      // Use Break Even
input int BreakEvenPips = 5;                         // Break Even Pips
input bool UseTrailingStop = true;                   // Use Trailing Stop
input int TrailingStopPips = 3;                      // Trailing Stop Pips

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

int barHandle = 0;
int volumeHandle = 0;
datetime lastTradeTime = 0;
double dailyLoss = 0;
datetime sessionStart;

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit() {
   // Initialize Trade class
   trade.SetExpertMagicNumber(20240905);
   trade.SetDeviationInPoints(10);
   trade.SetAsyncMode(false);
   
   // Request bars and volume data
   barHandle = iClose(_Symbol, _Period, 0);
   volumeHandle = iVolumes(_Symbol, _Period, VOLUME_REAL);
   
   if(barHandle == INVALID_HANDLE || volumeHandle == INVALID_HANDLE) {
      Print("Error: Failed to create handles");
      return INIT_FAILED;
   }
   
   sessionStart = iTime(_Symbol, PERIOD_D1, 0);
   
   Print("=== Gold Scalping EA Initialized ===");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", _Period);
   Print("Lot Size: ", LotSize);
   Print("TP: ", TakeProfitPips, " pips | SL: ", StopLossPips, " pips");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   if(barHandle != INVALID_HANDLE) ReleaseCopyIndicatorBuffer(barHandle);
   if(volumeHandle != INVALID_HANDLE) ReleaseCopyIndicatorBuffer(volumeHandle);
}

//+------------------------------------------------------------------+
//| EXPERT TICK                                                      |
//+------------------------------------------------------------------+
void OnTick() {
   // Update daily loss
   UpdateDailyLoss();
   
   // Check if we can trade
   if(!CanTrade()) return;
   
   // Get signal
   SignalData signal = GetSignal();
   
   // Process signal
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
   // Check account conditions
   if(AccountInfoDouble(ACCOUNT_EQUITY) <= 0) return false;
   
   // Check daily loss limit
   if(dailyLoss >= MaxDailyLoss) {
      Print("Daily loss limit reached: $", dailyLoss);
      return false;
   }
   
   // Check max concurrent trades
   if(CountOpenTrades() >= MaxTrades) return false;
   
   // Check time filter
   if(UseTimeFilter && !IsInTradingHours()) return false;
   
   // Check minimum time between trades (50ms)
   if(GetTickCount() - (int)lastTradeTime < 50) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| GET SIGNAL FUNCTION                                              |
//+------------------------------------------------------------------+
SignalData GetSignal() {
   SignalData signal;
   signal.type = SIGNAL_NONE;
   signal.strength = 0;
   signal.reason = "";
   signal.time = TimeCurrent();
   
   // Check if new bar
   if(iTime(_Symbol, _Period, 0) == lastTradeTime) return signal;
   
   // Get candle pattern
   int pattern = AnalyzeCandlePattern();
   
   // Get volume confirmation
   bool volumeConfirm = CheckVolumeConfirmation();
   
   if(!UseVolumeFilter) volumeConfirm = true;
   
   // Pin Bar Buy (Lower Wick)
   if(pattern == 1 && volumeConfirm) {
      signal.type = SIGNAL_BUY;
      signal.strength = 0.95;
      signal.reason = "Pin Bar at Support + High Volume";
   }
   // Pin Bar Sell (Upper Wick)
   else if(pattern == -1 && volumeConfirm) {
      signal.type = SIGNAL_SELL;
      signal.strength = 0.95;
      signal.reason = "Pin Bar at Resistance + High Volume";
   }
   // Engulfing Buy
   else if(pattern == 2 && volumeConfirm) {
      signal.type = SIGNAL_BUY;
      signal.strength = 0.90;
      signal.reason = "Bullish Engulfing + High Volume";
   }
   // Engulfing Sell
   else if(pattern == -2 && volumeConfirm) {
      signal.type = SIGNAL_SELL;
      signal.strength = 0.90;
      signal.reason = "Bearish Engulfing + High Volume";
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| ANALYZE CANDLE PATTERN                                           |
//+------------------------------------------------------------------+
int AnalyzeCandlePattern() {
   // Get candle data
   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   CopyOpen(_Symbol, _Period, 0, CandleAnalysisPeriod, open);
   CopyHigh(_Symbol, _Period, 0, CandleAnalysisPeriod, high);
   CopyLow(_Symbol, _Period, 0, CandleAnalysisPeriod, low);
   CopyClose(_Symbol, _Period, 0, CandleAnalysisPeriod, close);
   
   // Current candle
   double currOpen = open[0];
   double currHigh = high[0];
   double currLow = low[0];
   double currClose = close[0];
   
   // Previous candles
   double prevOpen = open[1];
   double prevHigh = high[1];
   double prevLow = low[1];
   double prevClose = close[1];
   
   double bodySize = MathAbs(currClose - currOpen);
   double totalSize = currHigh - currLow;
   double lowerWick = currOpen > currClose ? currClose - currLow : currOpen - currLow;
   double upperWick = currOpen > currClose ? currHigh - currOpen : currHigh - currClose;
   
   // Pin Bar Detection (Lower Wick - Buy)
   if(totalSize > 0 && (lowerWick / totalSize) > PinBarThreshold && 
      (bodySize / totalSize) < (1 - PinBarThreshold)) {
      if(lowerWick > upperWick) return 1; // Pin Bar Buy
   }
   
   // Pin Bar Detection (Upper Wick - Sell)
   if(totalSize > 0 && (upperWick / totalSize) > PinBarThreshold && 
      (bodySize / totalSize) < (1 - PinBarThreshold)) {
      if(upperWick > lowerWick) return -1; // Pin Bar Sell
   }
   
   // Engulfing Buy (Current Close > Prev Open)
   if(currClose > prevOpen && currOpen < prevClose && currOpen < prevLow) {
      double engulfingRatio = (currClose - currOpen) / (prevClose - prevOpen);
      if(engulfingRatio > EngulfingThreshold) return 2; // Engulfing Buy
   }
   
   // Engulfing Sell (Current Close < Prev Open)
   if(currClose < prevOpen && currOpen > prevClose && currOpen > prevHigh) {
      double engulfingRatio = (currOpen - currClose) / (prevOpen - prevClose);
      if(engulfingRatio > EngulfingThreshold) return -2; // Engulfing Sell
   }
   
   return 0; // No pattern
}

//+------------------------------------------------------------------+
//| CHECK VOLUME CONFIRMATION                                        |
//+------------------------------------------------------------------+
bool CheckVolumeConfirmation() {
   if(!UseVolumeFilter) return true;
   
   double volumes[];
   ArraySetAsSeries(volumes, true);
   
   if(CopyRealVolume(_Symbol, _Period, 0, VolumeMA + 1, volumes) < VolumeMA + 1) {
      return false;
   }
   
   // Calculate average volume
   double avgVolume = 0;
   for(int i = 1; i <= VolumeMA; i++) {
      avgVolume += volumes[i];
   }
   avgVolume /= VolumeMA;
   
   // Current volume should be higher than average
   if(volumes[0] > avgVolume * VolumeThreshold) {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| EXECUTE BUY SIGNAL                                               |
//+------------------------------------------------------------------+
void ExecuteBuySignal(SignalData &signal) {
   // Calculate SL and TP
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = ask - (StopLossPips * _Point);
   double takeProfit = ask + (TakeProfitPips * _Point);
   
   // Normalize prices
   stopLoss = NormalizePrice(stopLoss);
   takeProfit = NormalizePrice(takeProfit);
   
   // Execute buy order
   if(trade.Buy(LotSize, _Symbol, ask, stopLoss, takeProfit, signal.reason)) {
      Print("BUY Signal Executed: ", signal.reason);
      Print("Price: ", ask, " | TP: ", takeProfit, " | SL: ", stopLoss);
      lastTradeTime = GetTickCount();
   } else {
      Print("Buy Order Failed: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| EXECUTE SELL SIGNAL                                              |
//+------------------------------------------------------------------+
void ExecuteSellSignal(SignalData &signal) {
   // Calculate SL and TP
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = bid + (StopLossPips * _Point);
   double takeProfit = bid - (TakeProfitPips * _Point);
   
   // Normalize prices
   stopLoss = NormalizePrice(stopLoss);
   takeProfit = NormalizePrice(takeProfit);
   
   // Execute sell order
   if(trade.Sell(LotSize, _Symbol, bid, stopLoss, takeProfit, signal.reason)) {
      Print("SELL Signal Executed: ", signal.reason);
      Print("Price: ", bid, " | TP: ", takeProfit, " | SL: ", stopLoss);
      lastTradeTime = GetTickCount();
   } else {
      Print("Sell Order Failed: ", GetLastError());
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
      
      // Break Even Logic
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
      
      // Trailing Stop Logic
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
//| UPDATE DAILY LOSS                                                |
//+------------------------------------------------------------------+
void UpdateDailyLoss() {
   // Reset daily loss if new day
   if(iTime(_Symbol, PERIOD_D1, 0) != sessionStart) {
      dailyLoss = 0;
      sessionStart = iTime(_Symbol, PERIOD_D1, 0);
   }
   
   // Calculate loss from closed positions
   dailyLoss = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--) {
      if(!orderInfo.SelectByIndex(i)) continue;
      
      if(orderInfo.Symbol() == _Symbol && 
         orderInfo.Magic() == trade.GetMagicNumber() &&
         orderInfo.OrderCreateTime() >= sessionStart) {
         
         double profit = orderInfo.Profit();
         if(profit < 0) dailyLoss += MathAbs(profit);
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
//| ON TRADE EVENT                                                   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   // Log trade transactions for analysis
   if(trans.type == TRADE_TRANSACTION_ORDER_STATE) {
      if(trans.order_state == ORDER_STATE_FILLED) {
         Print("Order Filled - Ticket: ", trans.order, " | Price: ", trans.price);
      }
   }
}

//+------------------------------------------------------------------+
//| END OF EXPERT ADVISOR                                            |
//+------------------------------------------------------------------+
