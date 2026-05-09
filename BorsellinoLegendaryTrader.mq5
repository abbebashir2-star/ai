//+------------------------------------------------------------------+
//|                                  BorsellinoLegendaryTrader.mq5   |
//|                                  Copyright 2024, Trading AI      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading AI"
#property link      "https://www.mql5.com"
#property version   "1.10"
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

// --- Global Variables ---
double orbHigh = 0;
double orbLow = 0;
bool tradeTakenToday = false;
int streakLosses = 0;
int gannDir = 0;
datetime lastResetDay = 0;

CTrade trade;

// --- Indicator Handles ---
int handleGannH, handleGannL, handleVolMA;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   handleGannH = iMA(_Symbol, _Period, InpGannPeriod, 0, MODE_SMA, PRICE_HIGH);
   handleGannL = iMA(_Symbol, _Period, InpGannPeriod, 0, MODE_SMA, PRICE_LOW);
   handleVolMA = iMA(_Symbol, _Period, InpVolMA, 0, MODE_SMA, TICK_VOLUME);

   if(handleGannH == INVALID_HANDLE || handleGannL == INVALID_HANDLE || handleVolMA == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(123456);

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
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime currentDay = StructToTime(dt);

   // --- New Day Reset ---
   if(currentDay != lastResetDay)
   {
      orbHigh = 0;
      orbLow = 0;
      tradeTakenToday = false;
      lastResetDay = currentDay;
      Print("New day reset: ", TimeToString(currentDay));
   }

   // --- Update Gann Direction (State Machine) ---
   UpdateGannDir();

   // --- Opening Range Calculation ---
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

      if(currentTime < sessionStart + InpORBDuration * 60)
         return; // Still in ORB period
   }

   // --- Check Circuit Breaker ---
   CheckClosedTrades(); // Update streakLosses
   if(InpUseCircuitBreaker && streakLosses >= 3)
   {
      Comment("Circuit Breaker Active: 3 Consecutive Losses");
      return;
   }
   Comment("Borsellino EA Active\nORB High: ", orbHigh, "\nORB Low: ", orbLow, "\nStreak Losses: ", streakLosses);

   // --- Entry Logic ---
   if(!tradeTakenToday && !PositionExists())
   {
      double closePrice = iClose(_Symbol, _Period, 0);
      double closePrev = iClose(_Symbol, _Period, 1);

      // Buy Signal (Crossover ORB High)
      if(closePrev <= orbHigh && closePrice > orbHigh)
      {
         if(CheckFilters(1))
         {
            double sl = orbHigh - InpSLPoints * _Point;
            double tp = orbHigh + InpTPPoints * _Point;
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "Borsellino Buy"))
            {
               tradeTakenToday = true;
            }
         }
      }
      // Sell Signal (Crossunder ORB Low)
      else if(closePrev >= orbLow && closePrice < orbLow)
      {
         if(CheckFilters(-1))
         {
            double sl = orbLow + InpSLPoints * _Point;
            double tp = orbLow - InpTPPoints * _Point;
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "Borsellino Sell"))
            {
               tradeTakenToday = true;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update Gann Direction                                            |
//+------------------------------------------------------------------+
void UpdateGannDir()
{
   double gH[], gL[];
   // Copy index 1 (previous bar) to match gannH[1] in Pine Script
   if(CopyBuffer(handleGannH, 0, 1, 1, gH) > 0 && CopyBuffer(handleGannL, 0, 1, 1, gL) > 0)
   {
      double closeCurr = iClose(_Symbol, _Period, 0);
      if(closeCurr > gH[0]) gannDir = 1;
      else if(closeCurr < gL[0]) gannDir = -1;
   }
}

//+------------------------------------------------------------------+
//| Check Filters                                                    |
//+------------------------------------------------------------------+
bool CheckFilters(int side)
{
   // 1. Gann Filter
   if(InpUseGann)
   {
      if(side == 1 && gannDir != 1) return false;
      if(side == -1 && gannDir != -1) return false;
   }

   // 2. Volume Filter
   if(InpUseVol)
   {
      long vol = iTickVolume(_Symbol, _Period, 0);
      double volMA[];
      if(CopyBuffer(handleVolMA, 0, 0, 1, volMA) > 0)
      {
         if(vol < volMA[0] * InpVolMult) return false;
      }
   }

   // 3. Reversal Filter
   if(InpUseRev)
   {
      bool revFound = false;
      if(side == 1) // Need recent Pivot Low
      {
         for(int i = 2; i < InpRevLookback + 2; i++)
         {
            if(iLow(_Symbol, _Period, i) < iLow(_Symbol, _Period, i-1) &&
               iLow(_Symbol, _Period, i) < iLow(_Symbol, _Period, i-2) &&
               iLow(_Symbol, _Period, i) < iLow(_Symbol, _Period, i+1) &&
               iLow(_Symbol, _Period, i) < iLow(_Symbol, _Period, i+2))
            {
               revFound = true;
               break;
            }
         }
      }
      else if(side == -1) // Need recent Pivot High
      {
         for(int i = 2; i < InpRevLookback + 2; i++)
         {
            if(iHigh(_Symbol, _Period, i) > iHigh(_Symbol, _Period, i-1) &&
               iHigh(_Symbol, _Period, i) > iHigh(_Symbol, _Period, i-2) &&
               iHigh(_Symbol, _Period, i) > iHigh(_Symbol, _Period, i+1) &&
               iHigh(_Symbol, _Period, i) > iHigh(_Symbol, _Period, i+2))
            {
               revFound = true;
               break;
            }
         }
      }
      if(!revFound) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check Closed Trades for Streak                                   |
//+------------------------------------------------------------------+
void CheckClosedTrades()
{
   if(!HistorySelect(lastResetDay, TimeCurrent())) return;

   int total = HistoryDealsTotal();
   int tempStreak = 0;

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != 123456) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_COMMISSION) + HistoryDealGetDouble(ticket, DEAL_SWAP);
         if(profit < 0)
            tempStreak++;
         else if(profit > 0)
            break;
      }
   }
   streakLosses = tempStreak;
}

//+------------------------------------------------------------------+
//| Check if position exists for this EA                             |
//+------------------------------------------------------------------+
bool PositionExists()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == 123456 && PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   return false;
}
