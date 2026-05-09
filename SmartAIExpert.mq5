//+------------------------------------------------------------------+
//|                                              SmartAIExpert.mq5   |
//|                                  Copyright 2024, Trading AI      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading AI"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

// --- Inputs ---
input group "=== Risk Management ==="
input double InpLotSize = 0.10;         // Lot Size
input int    InpATRPeriod = 14;         // ATR Period for SL/TP
input double InpSLMultiplier = 1.5;     // SL ATR Multiplier
input double InpTPMultiplier = 3.0;     // TP ATR Multiplier

input group "=== Macro Intelligence ==="
input bool   InpUseCalendar = true;     // Use News Filter
input int    InpNewsPauseMin = 30;      // Pause before/after news (min)

input group "=== Machine Learning ==="
input bool   InpUseONNX = false;        // Use ML Model (Requires model.onnx)
input string InpModelPath = "model.onnx";

input group "=== Smart Technicals ==="
input int    InpOBBars = 50;            // Bars to look back for Order Blocks
input bool   InpUseFVG = true;          // Use Fair Value Gaps

// --- Global Variables ---
CTrade trade;
long   onnx_handle = INVALID_HANDLE;
int    handle_atr;
long   magic_number = 888888;

// --- Structures for SMC ---
struct OrderBlock {
   double price;
   datetime time;
   bool active;
   int side; // 1 for Bullish, -1 for Bearish
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // 1. Initialize Indicators
   handle_atr = iATR(_Symbol, _Period, InpATRPeriod);
   if(handle_atr == INVALID_HANDLE) return(INIT_FAILED);

   // 2. Initialize ONNX (Optional)
   if(InpUseONNX)
   {
      onnx_handle = OnnxCreate(InpModelPath, ONNX_DEFAULT);
      if(onnx_handle == INVALID_HANDLE)
      {
         Print("ONNX: Failed to load model. Continuing without ML.");
      }
      else
      {
         // Assuming input shape [1, 10] (10 previous candle changes)
         // and output shape [1, 1] (direction prediction)
         long input_shape[] = {1, 10};
         if(!OnnxSetInputShape(onnx_handle, 0, input_shape))
         {
             Print("ONNX: Failed to set input shape.");
             OnnxRelease(onnx_handle);
             onnx_handle = INVALID_HANDLE;
         }
      }
   }

   trade.SetExpertMagicNumber(magic_number);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handle_atr);
   if(onnx_handle != INVALID_HANDLE) OnnxRelease(onnx_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. News Filter
   if(InpUseCalendar && IsNewsTime()) return;

   // 2. ML Prediction (Filter)
   int ml_direction = 0; // 0: Neutral, 1: Bullish, -1: Bearish
   if(InpUseONNX && onnx_handle != INVALID_HANDLE)
   {
      ml_direction = GetMLPrediction();
   }

   // 3. Technical Analysis (SMC)
   bool fvg_buy = false, fvg_sell = false;
   if(InpUseFVG) CheckFVG(fvg_buy, fvg_sell);

   OrderBlock last_ob;
   FindLastOrderBlock(last_ob);

   // 4. Execution Logic
   if(!PositionExists())
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double atr[];
      CopyBuffer(handle_atr, 0, 0, 1, atr);

      // BUY Criteria:
      // - ML confirms Bullish (if used)
      // - Price is near a Bullish Order Block (Discount)
      // - FVG detected or passed
      bool buy_signal = (ml_direction >= 0) && (last_ob.side == 1 && ask <= last_ob.price + (atr[0]*0.5));
      if(InpUseFVG) buy_signal = buy_signal && fvg_buy;

      if(buy_signal)
      {
         double sl = ask - (atr[0] * InpSLMultiplier);
         double tp = ask + (atr[0] * InpTPMultiplier);
         trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "AI-SMC Buy");
      }

      // SELL Criteria:
      // - ML confirms Bearish (if used)
      // - Price is near a Bearish Order Block (Premium)
      // - FVG detected
      bool sell_signal = (ml_direction <= 0) && (last_ob.side == -1 && bid >= last_ob.price - (atr[0]*0.5));
      if(InpUseFVG) sell_signal = sell_signal && fvg_sell;

      if(sell_signal)
      {
         double sl = bid + (atr[0] * InpSLMultiplier);
         double tp = bid - (atr[0] * InpTPMultiplier);
         trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "AI-SMC Sell");
      }
   }
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
         if(PositionGetInteger(POSITION_MAGIC) == magic_number && PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check for News Events                                            |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   MqlCalendarValue values[];
   datetime from = TimeCurrent();
   datetime to = from + InpNewsPauseMin * 60;

   // Check upcoming news
   if(CalendarValueHistory(values, from, to) > 0)
   {
      for(int i=0; i<ArraySize(values); i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH) return true;
         }
      }
   }

   // Check recent news
   from = TimeCurrent() - InpNewsPauseMin * 60;
   to = TimeCurrent();
   if(CalendarValueHistory(values, from, to) > 0)
   {
      for(int i=0; i<ArraySize(values); i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH) return true;
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Get ML Prediction from ONNX                                      |
//+------------------------------------------------------------------+
int GetMLPrediction()
{
   float input_data[10];
   float output_data[1];

   for(int i=0; i<10; i++)
   {
      input_data[i] = (float)(iClose(_Symbol, _Period, i) - iOpen(_Symbol, _Period, i));
   }

   if(OnnxRun(onnx_handle, ONNX_NO_LOGS, input_data, output_data))
   {
      if(output_data[0] > 0.5) return 1;
      if(output_data[0] < -0.5) return -1;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Detect Fair Value Gaps (FVG)                                     |
//+------------------------------------------------------------------+
void CheckFVG(bool &buy, bool &sell)
{
   buy = false; sell = false;
   // Bullish FVG: Bar 1 Low > Bar 3 High
   if(iLow(_Symbol, _Period, 1) > iHigh(_Symbol, _Period, 3)) buy = true;
   // Bearish FVG: Bar 1 High < Bar 3 Low
   if(iHigh(_Symbol, _Period, 1) < iLow(_Symbol, _Period, 3)) sell = true;
}

//+------------------------------------------------------------------+
//| Find the Last Significant Order Block                            |
//+------------------------------------------------------------------+
void FindLastOrderBlock(OrderBlock &ob)
{
   ob.active = false;
   for(int i=1; i<InpOBBars; i++)
   {
      // Simplistic OB: Last candle of opposite color before a break of structure
      // Bullish OB: Last bearish candle before a strong impulsive bullish move
      if(iClose(_Symbol, _Period, i) < iOpen(_Symbol, _Period, i) &&
         iClose(_Symbol, _Period, i-1) > iHigh(_Symbol, _Period, i))
      {
         ob.price = iHigh(_Symbol, _Period, i);
         ob.side = 1;
         ob.active = true;
         break;
      }
      // Bearish OB
      if(iClose(_Symbol, _Period, i) > iOpen(_Symbol, _Period, i) &&
         iClose(_Symbol, _Period, i-1) < iLow(_Symbol, _Period, i))
      {
         ob.price = iLow(_Symbol, _Period, i);
         ob.side = -1;
         ob.active = true;
         break;
      }
   }
}
