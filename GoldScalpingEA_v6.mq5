//+------------------------------------------------------------------+
//|                  Gold Scalping EA v6.0 REAL WORKING              |
//|              RSI + MACD + Support/Resistance                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "6.0"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;
input double LotSize = 1.0;
input double TPPips = 25;
input double SLPips = 8;
input int MaxTrades = 15;
input int RSIPeriod = 14;
input int MACDFast = 12;
input int MACDSlow = 26;
input int MACDSignal = 9;

int MagicNumber = 20240906;
datetime lastBarTime = 0;

// Indicator handles
int rsiHandle;
int macdHandle;

int OnInit() {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   
   // Create indicator handles
   rsiHandle = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);
   macdHandle = iMACD(_Symbol, _Period, MACDFast, MACDSlow, MACDSignal, PRICE_CLOSE);
   
   if(rsiHandle == INVALID_HANDLE || macdHandle == INVALID_HANDLE) {
      Print("Error creating indicators");
      return INIT_FAILED;
   }
   
   Print("=== Gold EA v6.0 Started ===");
   Print("RSI(", RSIPeriod, ") + MACD(", MACDFast, ",", MACDSlow, ",", MACDSignal, ")");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(macdHandle != INVALID_HANDLE) IndicatorRelease(macdHandle);
   Print("EA Stopped");
}

void OnTick() {
   if(Bars(_Symbol, _Period) < 100) return;
   
   if(iTime(_Symbol, _Period, 0) == lastBarTime) return;
   lastBarTime = iTime(_Symbol, _Period, 0);
   
   if(CountTrades() >= MaxTrades) return;
   
   // Get RSI values
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(rsiHandle, 0, 0, 3, rsi) < 3) return;
   
   // Get MACD values
   double macdMain[];
   double macdSignal[];
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   
   if(CopyBuffer(macdHandle, 0, 0, 3, macdMain) < 3) return;
   if(CopyBuffer(macdHandle, 1, 0, 3, macdSignal) < 3) return;
   
   double signal = GetSignalRSI_MACD(rsi, macdMain, macdSignal);
   
   if(signal == 1.0) {
      BuyOrder();
   }
   else if(signal == -1.0) {
      SellOrder();
   }
   
   ManageTrades();
}

double GetSignalRSI_MACD(double &rsi[], double &macdMain[], double &macdSignal[]) {
   // RSI Oversold/Overbought
   double rsi0 = rsi[0];
   double rsi1 = rsi[1];
   
   // MACD Crossover
   double macd0 = macdMain[0];
   double macdSig0 = macdSignal[0];
   double macd1 = macdMain[1];
   double macdSig1 = macdSignal[1];
   
   // BUY SIGNALS
   // 1. RSI crosses above 30 (from oversold)
   if(rsi1 < 30 && rsi0 > 30 && rsi0 < 50) {
      Print("RSI Buy Signal: ", rsi0);
      return 1.0;
   }
   
   // 2. MACD crosses above signal line
   if(macd1 < macdSig1 && macd0 > macdSig0 && macd0 > 0) {
      Print("MACD Buy Signal: ", macd0);
      return 1.0;
   }
   
   // 3. Both RSI and MACD bullish
   if(rsi0 > 30 && rsi0 < 70 && macd0 > macdSig0 && macd0 > 0) {
      Print("RSI+MACD Buy");
      return 1.0;
   }
   
   // SELL SIGNALS
   // 1. RSI crosses below 70 (from overbought)
   if(rsi1 > 70 && rsi0 < 70 && rsi0 > 50) {
      Print("RSI Sell Signal: ", rsi0);
      return -1.0;
   }
   
   // 2. MACD crosses below signal line
   if(macd1 > macdSig1 && macd0 < macdSig0 && macd0 < 0) {
      Print("MACD Sell Signal: ", macd0);
      return -1.0;
   }
   
   // 3. Both RSI and MACD bearish
   if(rsi0 < 70 && rsi0 > 30 && macd0 < macdSig0 && macd0 < 0) {
      Print("RSI+MACD Sell");
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
      Print("✅ BUY at ", ask);
   } else {
      Print("❌ BUY Failed");
   }
}

void SellOrder() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = bid + (SLPips * point);
   double tp = bid - (TPPips * point);
   
   if(trade.Sell(LotSize, _Symbol, bid, sl, tp)) {
      Print("✅ SELL at ", bid);
   } else {
      Print("❌ SELL Failed");
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
      
      if(pos.PositionType() == POSITION_TYPE_BUY) {
         if(ask > openPrice + (3 * point) && sl < openPrice) {
            trade.PositionModify(ticket, openPrice, tp);
         }
      }
      else {
         if(bid < openPrice - (3 * point) && sl > openPrice) {
            trade.PositionModify(ticket, openPrice, tp);
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
