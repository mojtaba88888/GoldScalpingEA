//+------------------------------------------------------------------+
//|                  Gold Scalping EA v5.0 WORKING                   |
//|              WITH REAL TRADING SIGNALS                           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "5.0"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;
input double LotSize = 1.0;
input double TPPips = 30;
input double SLPips = 4;
input int MaxTrades = 12;
int MagicNumber = 20240906;
datetime lastBarTime = 0;
int signalCount = 0;

int OnInit() {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   Print("=== Gold EA v5.0 Started ===");
   Print("Lot: ", LotSize, " | TP: ", TPPips, "pips | SL: ", SLPips, "pips");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   Print("=== EA Stopped ===");
}

void OnTick() {
   if(Bars(_Symbol, _Period) < 10) return;
   
   if(iTime(_Symbol, _Period, 0) == lastBarTime) return;
   lastBarTime = iTime(_Symbol, _Period, 0);
   
   if(CountTrades() >= MaxTrades) return;
   
   double signal = GetSignal();
   
   if(signal == 1.0) {
      BuyOrder();
      signalCount++;
   }
   else if(signal == -1.0) {
      SellOrder();
      signalCount++;
   }
   
   ManageTrades();
}

double GetSignal() {
   double close2 = iClose(_Symbol, _Period, 2);
   double close1 = iClose(_Symbol, _Period, 1);
   double close0 = iClose(_Symbol, _Period, 0);
   
   double open1 = iOpen(_Symbol, _Period, 1);
   double open0 = iOpen(_Symbol, _Period, 0);
   
   double high1 = iHigh(_Symbol, _Period, 1);
   double low1 = iLow(_Symbol, _Period, 1);
   double high0 = iHigh(_Symbol, _Period, 0);
   double low0 = iLow(_Symbol, _Period, 0);
   
   double body0 = MathAbs(close0 - open0);
   double body1 = MathAbs(close1 - open1);
   double range0 = high0 - low0;
   double range1 = high1 - low1;
   
   // SIMPLIFIED PIN BAR - More trades
   // Pin Bar Buy (Lower wick)
   if(range0 > 0) {
      double lowerWick = (open0 > close0) ? (close0 - low0) : (open0 - low0);
      double upperWick = (open0 > close0) ? (high0 - open0) : (high0 - close0);
      
      // Buy: Lower wick > 40% of range AND body small
      if(lowerWick > range0 * 0.4 && body0 < range0 * 0.4) {
         if(lowerWick > upperWick) {
            Print("Pin Bar BUY detected at ", close0);
            return 1.0;
         }
      }
      
      // Sell: Upper wick > 40% of range AND body small
      if(upperWick > range0 * 0.4 && body0 < range0 * 0.4) {
         if(upperWick > lowerWick) {
            Print("Pin Bar SELL detected at ", close0);
            return -1.0;
         }
      }
   }
   
   // SIMPLIFIED ENGULFING - More trades
   if(range1 > 0 && body1 > 0) {
      // Bullish Engulfing: Current close > previous open AND current open < previous close
      if(close0 > open1 && open0 < close1) {
         // Just check body bigger
         if(body0 > body1 * 0.6) {
            Print("Engulfing BUY detected at ", close0);
            return 1.0;
         }
      }
      
      // Bearish Engulfing
      if(close0 < open1 && open0 > close1) {
         if(body0 > body1 * 0.6) {
            Print("Engulfing SELL detected at ", close0);
            return -1.0;
         }
      }
   }
   
   // SIMPLE TREND - More trades
   // Buy: 3 candles closing higher
   if(close2 < close1 && close1 < close0) {
      Print("Uptrend BUY at ", close0);
      return 1.0;
   }
   
   // Sell: 3 candles closing lower
   if(close2 > close1 && close1 > close0) {
      Print("Downtrend SELL at ", close0);
      return -1.0;
   }
   
   return 0;
}

void BuyOrder() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = ask - (SLPips * point);
   double tp = ask + (TPPips * point);
   
   if(trade.Buy(LotSize, _Symbol, ask, sl, tp)) {
      Print("✅ BUY Order Placed at ", ask);
   } else {
      Print("❌ BUY Failed: ", trade.ResultRetcode());
   }
}

void SellOrder() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = bid + (SLPips * point);
   double tp = bid - (TPPips * point);
   
   if(trade.Sell(LotSize, _Symbol, bid, sl, tp)) {
      Print("✅ SELL Order Placed at ", bid);
   } else {
      Print("❌ SELL Failed: ", trade.ResultRetcode());
   }
}

void ManageTrades() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      CPositionInfo pos;
      if(!pos.SelectByIndex(i)) continue;
      
      if(pos.Symbol() != _Symbol) continue;
      if(pos.Magic() != MagicNumber) continue;
      
      ulong ticket = pos.Ticket();
      double openPrice = pos.PriceOpen();
      double sl = pos.StopLoss();
      double tp = pos.TakeProfit();
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      // Break Even at +2 pips
      if(pos.PositionType() == POSITION_TYPE_BUY) {
         if(ask > openPrice + (2 * point)) {
            if(sl < openPrice) {
               trade.PositionModify(ticket, openPrice + 1 * point, tp);
            }
         }
      }
      else {
         if(bid < openPrice - (2 * point)) {
            if(sl > openPrice) {
               trade.PositionModify(ticket, openPrice - 1 * point, tp);
            }
         }
      }
   }
}

int CountTrades() {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      CPositionInfo pos;
      if(pos.SelectByIndex(i)) {
         if(pos.Symbol() == _Symbol && pos.Magic() == MagicNumber) {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
