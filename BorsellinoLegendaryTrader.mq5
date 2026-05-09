//+------------------------------------------------------------------+
//|                                  BorsellinoLegendaryTrader.mq5   |
//|                                  Copyright 2024, Trading AI      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading AI"
#property link      "https://www.mql5.com"
#property version   "1.30"
#property strict

#include <Trade\Trade.mqh>

// --- Inputs ---
input group "1. Opening Range Settings"
input int InpORBDuration = 5;          // ORB Duration (Minutes)

input group "2. Gann Filter Settings"
input bool InpUseGann = true;          // Use Gann Hi-Lo Filter
input int InpGannPeriod = 3;           // Gann Period

input group "3. Reversal Filter Settings"
input bool InpUseRev = true;           // Use Reversal Confirmation
input int InpRevLookback = 10;         // Reversal Lookback

input group "4. Order Flow (Volume) Settings"
input bool InpUseVol = true;           // Use Order Flow Confirmation
input int InpVolMA = 20;               // Volume MA Length
input double InpVolMult = 1.2;         // Volume Multiplier

input group "5. Risk & Management"
input double InpLotSize = 0.10;        // Lot Size
input int InpSLPoints = 600;           // Stop Loss Points
input int InpTPPoints = 1000;          // Profit Target Points
input bool InpUseCircuitBreaker = true; // 3 Losses Stop Trading
input long InpMagic = 123456;          // Magic Number

// --- Global Variables ---
double orbHigh = 0;
double orbLow = 0;
bool tradeTakenToday = false;
int streakLosses = 0;
int gannDir = 0;
datetime lastResetDay = 0;

CTrade trade;

// --- Indicator Handles ---
int handleGannH, handleGannL, handleVolMA, handleVol;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   handleGannH = iMA(_Symbol, _Period, InpGannPeriod, 0, MODE_SMA, PRICE_HIGH);
   handleGannL = iMA(_Symbol, _Period, InpGannPeriod, 0, MODE_SMA, PRICE_LOW);

   handleVol = iVolumes(_Symbol, _Period, VOLUME_TICK);
   handleVolMA = iMA(_Symbol, _Period, InpVolMA, 0, MODE_SMA, handleVol);

   if(handleGannH == INVALID_HANDLE || handleGannL == INVALID_HANDLE ||
      handleVol == INVALID_HANDLE || handleVolMA == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InpMagic);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleGannH);
   IndicatorRelease(handleGannL);
   IndicatorRelease(handleVolMA);
   IndicatorRelease(handleVol);
}

//+------------------------------------------------------------------+
//| Helper to get MQL5 data safely                                   |
//+------------------------------------------------------------------+
double GetClose(int index) { double res[]; return (CopyClose(_Symbol, _Period, index, 1, res) > 0) ? res[0] : 0; }
double GetOpen(int index) { double res[]; return (CopyOpen(_Symbol, _Period, index, 1, res) > 0) ? res[0] : 0; }
double GetHigh(int index) { double res[]; return (CopyHigh(_Symbol, _Period, index, 1, res) > 0) ? res[0] : 0; }
double GetLow(int index) { double res[]; return (CopyLow(_Symbol, _Period, index, 1, res) > 0) ? res[0] : 0; }
long GetTickVolume(int index) { long res[]; return (CopyTickVolume(_Symbol, _Period, index, 1, res) > 0) ? res[0] : 0; }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime currentDay = StructToTime(dt);

   if(currentDay != lastResetDay)
   {
      orbHigh = 0; orbLow = 0; tradeTakenToday = false;
      lastResetDay = currentDay;
   }

   UpdateGannDir();

   datetime sessionStart = currentDay;
   datetime currentTime = TimeCurrent();

   if(orbHigh == 0 || orbLow == 0 || currentTime < sessionStart + InpORBDuration * 60)
   {
      double highs[], lows[];
      int copied = CopyHigh(_Symbol, PERIOD_M1, sessionStart, InpORBDuration, highs);
      CopyLow(_Symbol, PERIOD_M1, sessionStart, InpORBDuration, lows);
      if(copied > 0)
      {
         orbHigh = highs[ArrayMaximum(highs)];
         orbLow = lows[ArrayMinimum(lows)];
      }
      if(currentTime < sessionStart + InpORBDuration * 60) return;
   }

   CheckClosedTrades();
   if(InpUseCircuitBreaker && streakLosses >= 3)
   {
      Comment("Circuit Breaker Active: 3 Consecutive Losses");
      return;
   }
   Comment("Borsellino EA Active\nORB High: ", orbHigh, "\nORB Low: ", orbLow, "\nStreak Losses: ", streakLosses);

   if(!tradeTakenToday && !PositionExists())
   {
      double closePrice = GetClose(0);
      double closePrev = GetClose(1);

      if(closePrev <= orbHigh && closePrice > orbHigh)
      {
         if(CheckFilters(1))
         {
            double sl = orbHigh - InpSLPoints * _Point;
            double tp = orbHigh + InpTPPoints * _Point;
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "Borsellino Buy")) tradeTakenToday = true;
         }
      }
      else if(closePrev >= orbLow && closePrice < orbLow)
      {
         if(CheckFilters(-1))
         {
            double sl = orbLow + InpSLPoints * _Point;
            double tp = orbLow - InpTPPoints * _Point;
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "Borsellino Sell")) tradeTakenToday = true;
         }
      }
   }
}

void UpdateGannDir()
{
   double gH[], gL[];
   if(CopyBuffer(handleGannH, 0, 1, 1, gH) > 0 && CopyBuffer(handleGannL, 0, 1, 1, gL) > 0)
   {
      double closeCurr = GetClose(0);
      if(closeCurr > gH[0]) gannDir = 1;
      else if(closeCurr < gL[0]) gannDir = -1;
   }
}

bool CheckFilters(int side)
{
   if(InpUseGann)
   {
      if(side == 1 && gannDir != 1) return false;
      if(side == -1 && gannDir != -1) return false;
   }

   if(InpUseVol)
   {
      long vol = GetTickVolume(0);
      double volMA[];
      if(CopyBuffer(handleVolMA, 0, 0, 1, volMA) > 0)
      {
         if(vol < volMA[0] * InpVolMult) return false;
      }
   }

   if(InpUseRev)
   {
      bool revFound = false;
      if(side == 1)
      {
         for(int i = 2; i < InpRevLookback + 2; i++)
         {
            if(GetLow(i) < GetLow(i-1) && GetLow(i) < GetLow(i-2) && GetLow(i) < GetLow(i+1) && GetLow(i) < GetLow(i+2))
            {
               revFound = true; break;
            }
         }
      }
      else
      {
         for(int i = 2; i < InpRevLookback + 2; i++)
         {
            if(GetHigh(i) > GetHigh(i-1) && GetHigh(i) > GetHigh(i-2) && GetHigh(i) > GetHigh(i+1) && GetHigh(i) > GetHigh(i+2))
            {
               revFound = true; break;
            }
         }
      }
      if(!revFound) return false;
   }
   return true;
}

void CheckClosedTrades()
{
   if(!HistorySelect(lastResetDay, TimeCurrent())) return;
   int total = HistoryDealsTotal();
   int tempStreak = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_COMMISSION) + HistoryDealGetDouble(ticket, DEAL_SWAP);
         if(profit < 0) tempStreak++;
         else if(profit > 0) break;
      }
   }
   streakLosses = tempStreak;
}

bool PositionExists()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   return false;
}
