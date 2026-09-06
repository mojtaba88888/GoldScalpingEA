//+------------------------------------------------------------------+
//|                  Gold Scalping EA FINAL v4.0                     |
//|              SIMPLIFIED & PRODUCTION READY                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "4.0"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;
double LotSize = 1.0;
double TPPips = 30;
double SLPips = 4;
int MaxTrades = 12;
int MagicNumber = 20240906;
datetime lastBarTime = 0;

int OnInit() {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   Print("Gold EA v4.0 Started");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   Print("EA Stopped");
}

void OnTick() {
   if(Bars(_Symbol, _Period) < 50) return;
   
   if(iTime(_Symbol, _Period, 0) == lastBarTime) return;
   lastBarTime = iTime(_Symbol, _Period, 0);
   
   if(CountTrades() >= MaxTrades) return;
   
   double signal = GetSignal();
   
   if(signal == 1.0) {
      BuyOrder();
   }
   else if(signal == -1.0) {
      SellOrder();
   }
   
   ManageTrades();
}

double GetSignal() {
   double open1 = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double high1 = iHigh(_Symbol, _Period, 1);
   double low1 = iLow(_Symbol, _Period, 1);
   
   double open0 = iOpen(_Symbol, _Period, 0);
   double close0 = iClose(_Symbol, _Period, 0);
   double high0 = iHigh(_Symbol, _Period, 0);
   double low0 = iLow(_Symbol, _Period, 0);
   
   double body0 = MathAbs(close0 - open0);
   double body1 = MathAbs(close1 - open1);
   double range0 = high0 - low0;
   double range1 = high1 - low1;
   
   if(range0 == 0 || range1 == 0) return 0;
   
   // Pin Bar Buy
   double lowerWick0 = (open0 > close0) ? (close0 - low0) : (open0 - low0);
   double upperWick0 = (open0 > close0) ? (high0 - open0) : (high0 - close0);
   
   if(lowerWick0 > range0 * 0.5 && body0 < range0 * 0.5 && lowerWick0 > upperWick0) {
      return 1.0;
   }
   
   // Pin Bar Sell
   if(upperWick0 > range0 * 0.5 && body0 < range0 * 0.5 && upperWick0 > lowerWick0) {
      return -1.0;
   }
   
   // Engulfing Buy
   if(close0 > open1 && open0 < close1 && body0 > body1 * 0.7) {
      return 1.0;
   }
   
   // Engulfing Sell
   if(close0 < open1 && open0 > close1 && body0 > body1 * 0.7) {
      return -1.0;
   }
   
   return 0;
}

void BuyOrder() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = ask - (SLPips * point);
   double tp = ask + (TPPips * point);
   
   trade.Buy(LotSize, _Symbol, ask, sl, tp, "Buy Signal");
}

void SellOrder() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = bid + (SLPips * point);
   double tp = bid - (TPPips * point);
   
   trade.Sell(LotSize, _Symbol, bid, sl, tp, "Sell Signal");
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
      
      // Break Even
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
