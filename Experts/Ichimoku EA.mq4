//+------------------------------------------------------------------+
//|                                  Ichimoku EA(only USD&JPY pairs) |
//|                                           Copyright 2017, Shk0da |
//|                                       https://github.com/Shk0da/ |
//+------------------------------------------------------------------+
#include <stdlib.mqh>
#include <stderror.mqh> 
#property copyright ""
#property link ""

// ------------------------------------------------------------------------------------------------
// EXTERNAL VARIABLES
// ------------------------------------------------------------------------------------------------

extern int magic=19274;
// Configuration
extern string CommonSettings="---------------------------------------------";
extern int user_slippage=2;
extern int user_tp=20;
extern int user_sl=60;
extern bool use_basic_tp=1;
extern bool use_basic_sl=0;
extern bool use_dynamic_tp=1;
extern bool use_dynamic_sl=1;
extern string MoneyManagementSettings="---------------------------------------------";
// Money Management
extern double min_lots=0.01;
extern int risk=7;
extern double balance_limit=50;
extern int max_orders = 5;
extern int expire_days=0;
// Indicators
int shift=1;
int atr_period=14;
// Trailing stop
extern string TrailingStopSettings="---------------------------------------------";
extern bool ts_enable=1;
extern int ts_val=15;
extern int ts_step=2;
extern bool ts_only_profit=1;
// ------------------------------------------------------------------------------------------------
// GLOBAL VARIABLES
// ------------------------------------------------------------------------------------------------

string key="Ichimoku EA: ";
int DAY=86400;
int order_ticket;
double order_lots;
double order_price;
double order_profit;
int order_time;
double signal;
int orders=0;
int direction=0;
double max_profit=0;
double close_profit=0;
double last_order_profit=0;
double last_order_lots=0;
color c=Black;
double balance;
double equity;
int slippage=0;
// OrderReliable
int retry_attempts= 10;
double sleep_time = 4.0;
double sleep_maximum=25.0;  // in seconds
string OrderReliable_Fname="OrderReliable fname unset";
static int _OR_err=0;
string OrderReliableVersion="V1_1_1";
// ------------------------------------------------------------------------------------------------
// START
// ------------------------------------------------------------------------------------------------
int start()
  {

   if(AccountBalance()<=balance_limit)
     {
      Alert("Balance: "+AccountBalance());
      return(0);
     }

   int ticket,i,n;
   double price;
   bool cerrada,encontrada;

   if(MarketInfo(Symbol(),MODE_DIGITS)==4)
     {
      slippage=user_slippage;
     }
   else if(MarketInfo(Symbol(),MODE_DIGITS)==5)
     {
      slippage=10*user_slippage;
     }

   if(IsTradeAllowed()==false)
     {
      Comment("Trade not allowed.");
      return;
     }

   Comment("\nIchimoku EA is running.");

   InicializarVariables();
   ActualizarOrdenes();

   encontrada=FALSE;
   if(OrdersHistoryTotal()>0)
     {
      i=1;

      while(i<=100 && encontrada==FALSE)
        {
         n=OrdersHistoryTotal()-i;
         if(OrderSelect(n,SELECT_BY_POS,MODE_HISTORY)==TRUE)
           {
            if(OrderMagicNumber()==magic)
              {
               encontrada=TRUE;
               last_order_profit=OrderProfit();
               last_order_lots=OrderLots();
              }
           }
         i++;
        }
     }

   closeExpiredOrders();
   Trade();

   return(0);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void closeExpiredOrders()
  {
   if(expire_days == 0) return;

   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
        {
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==magic && OrderOpenTime()<(TimeCurrent()-DAY*expire_days))
           {
            if(OrderType()==OP_BUY)
              {
               OrderCloseReliable(OrderTicket(),OrderLots(),MarketInfo(Symbol(),MODE_BID),slippage,Blue);
              }
            if(OrderType()==OP_SELL)
              {
               OrderCloseReliable(OrderTicket(),OrderLots(),MarketInfo(Symbol(),MODE_ASK),slippage,Red);
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Суммарный профит открытых позиций                                |
//+------------------------------------------------------------------+
double GetPfofit(int op)
  {
   double profit=0;
   int i;

   for(i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
        {
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==magic && OrderType()==op)
           {
            profit+=OrderProfit()+OrderSwap()-OrderCommission();
           }
        }
     }
   return(profit);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TrailingStop()
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
        {
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==magic)
           {
            TrailingPositions();
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Position maintenance simple trawl                             |
//+------------------------------------------------------------------+
void TrailingPositions()
  {
   double pBid,pAsk,pp;
//----
   pp=MarketInfo(OrderSymbol(),MODE_POINT);

   double val;
   int stop_level=MarketInfo(Symbol(),MODE_STOPLEVEL)+MarketInfo(Symbol(),MODE_SPREAD);
   if(use_dynamic_sl==1)
     {
      double atr=iATR(Symbol(),0,atr_period,shift)/0.00001;
      if(atr<stop_level) atr=stop_level;
      val=atr;
        } else {
      if(ts_val<stop_level) ts_val=stop_level;
      val=ts_val;
     }

   if(OrderType()==OP_BUY)
     {
      pBid=MarketInfo(OrderSymbol(),MODE_BID);
      if(!ts_only_profit || (pBid-OrderOpenPrice())>val*pp)
        {
         if(OrderStopLoss()<pBid-(val+ts_step-1)*pp)
           {
            ModifyStopLoss(pBid-val*pp);
            return;
           }
        }
     }
   if(OrderType()==OP_SELL)
     {
      pAsk=MarketInfo(OrderSymbol(),MODE_ASK);
      if(!ts_only_profit || OrderOpenPrice()-pAsk>val*pp)
        {
         if(OrderStopLoss()>pAsk+(val+ts_step-1)*pp || OrderStopLoss()==0)
           {
            ModifyStopLoss(pAsk+val*pp);
            return;
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| The transfer of the StopLoss level                                          |
//| Settings:                                                       |
//|   ldStopLoss - level StopLoss                                  |
//+------------------------------------------------------------------+
void ModifyStopLoss(double ldStopLoss)
  {
   OrderModify(OrderTicket(),OrderOpenPrice(),ldStopLoss,OrderTakeProfit(),0,CLR_NONE);
  }
//+------------------------------------------------------------------+

// ------------------------------------------------------------------------------------------------
// INITIALIZE VARIABLES
// ------------------------------------------------------------------------------------------------
void InicializarVariables()
  {
   orders=0;
   direction=0;
   order_ticket=0;
   order_lots=0;
   order_price= 0;
   order_time = 0;
   order_profit=0;
   last_order_profit=0;
   last_order_lots=0;
  }
// ------------------------------------------------------------------------------------------------
// ACTUALIZAR ORDENES
// ------------------------------------------------------------------------------------------------
void ActualizarOrdenes()
  {
   int ordenes=0;

   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==true)
        {
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==magic)
           {
            order_ticket=OrderTicket();
            order_lots=OrderLots();
            order_price= OrderOpenPrice();
            order_time = OrderOpenTime();
            order_profit=OrderProfit();
            ordenes++;
            if(OrderType()==OP_BUY) direction=1;
            if(OrderType()==OP_SELL) direction=2;
           }
        }
     }

   orders=ordenes;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetMaxLot(int Risk)
  {
   double Free=AccountFreeMargin();
   double margin=MarketInfo(Symbol(),MODE_MARGINREQUIRED);
   double Step= MarketInfo(Symbol(),MODE_LOTSTEP);
   double Lot = MathFloor(Free*Risk/100/margin/Step)*Step;
   if(Lot*margin>Free) return(0);
   return(Lot);
  }
// ------------------------------------------------------------------------------------------------
// CALCULATE VOLUME
// ------------------------------------------------------------------------------------------------
double CalcularVolumen()
  {
   int n;
   double aux;
   if(last_order_profit<0)
     {
      aux=last_order_lots*2;
     }
   else
     {
      aux= risk*AccountFreeMargin();
      aux= aux/100000;
      n=MathFloor(aux/min_lots);
      if(n>GetMaxLot(risk)) n=GetMaxLot(risk);
      aux=n*min_lots;
     }

   if(aux<min_lots) aux=min_lots;

   if(aux>MarketInfo(Symbol(),MODE_MAXLOT))
      aux=MarketInfo(Symbol(),MODE_MAXLOT);

   if(aux<MarketInfo(Symbol(),MODE_MINLOT))
      aux=MarketInfo(Symbol(),MODE_MINLOT);

   return(aux);
  }
// ------------------------------------------------------------------------------------------------
// CALCULATED TAKE PROFIT
// ------------------------------------------------------------------------------------------------
double GetTakeProfit(int op)
  {
   if(use_basic_tp == 0) return(0);

   double aux_take_profit=0;
   double spread=Ask-Bid;
   double val;

   int stop_level=MarketInfo(Symbol(),MODE_STOPLEVEL)+MarketInfo(Symbol(),MODE_SPREAD);
   if(use_dynamic_tp==1)
     {
      double atr=iATR(Symbol(),0,atr_period,shift)/0.00001;
      if(atr<stop_level) atr=stop_level;
      val=atr*Point;
        } else {
      if(user_tp<stop_level) user_tp=stop_level;
      val=user_tp*Point;
     }

   if(op==OP_BUY)
     {
      aux_take_profit=MarketInfo(Symbol(),MODE_ASK)+spread+val;
        } else if(op==OP_SELL) {
      aux_take_profit=MarketInfo(Symbol(),MODE_BID)-spread-val;
     }

   return(aux_take_profit);
  }
// ------------------------------------------------------------------------------------------------
// CALCULATES STOP LOSS
// ------------------------------------------------------------------------------------------------
double GetStopLoss(int op)
  {
   if(use_basic_sl == 0) return(0);

   double aux_stop_loss=0;

   double val;
   int stop_level=MarketInfo(Symbol(),MODE_STOPLEVEL)+MarketInfo(Symbol(),MODE_SPREAD);
   if(use_dynamic_sl==1)
     {
      double atr=iATR(Symbol(),0,atr_period,shift)/0.00001;
      if(atr<stop_level) atr=stop_level;
      val=atr*Point;
        } else {
      if(user_sl<stop_level) user_sl=stop_level;
      val=user_sl*Point;
     }

   if(op==OP_BUY)
     {
      aux_stop_loss=MarketInfo(Symbol(),MODE_ASK)-val;
        } else if(op==OP_SELL) {
      aux_stop_loss=MarketInfo(Symbol(),MODE_BID)+val;
     }

   return(aux_stop_loss);
  }
// ------------------------------------------------------------------------------------------------
// CALCULATED SIGNAL 
// ------------------------------------------------------------------------------------------------
double scalp1 = 0;
double scalp2 = 0;
double fisher1 = 0;
double fisher2 = 0;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int CalculaSignal()
  {
   if(AccountBalance()<=balance_limit)
     {
      return(0);
     }

   int aux_tenkan_sen=9;
   double aux_kijun_sen=26;
   double aux_senkou_span=52;
   int aux_shift=1;
   int aux=0;
   double kt1=0,kb1=0,kt2=0,kb2=0;
   double ts1,ts2,ks1,ks2,ssA1,ssA2,ssB1,ssB2,close1,close2;

   ts1 = iIchimoku(Symbol(), 0, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_TENKANSEN, aux_shift);
   ks1 = iIchimoku(Symbol(), 0, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_KIJUNSEN, aux_shift);
   ssA1 = iIchimoku(Symbol(), 0, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_SENKOUSPANA, aux_shift);
   ssB1 = iIchimoku(Symbol(), 0, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_SENKOUSPANB, aux_shift);
   close1=iClose(Symbol(),0,aux_shift);

   ts2 = iIchimoku(Symbol(), 0, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_TENKANSEN, aux_shift+1);
   ks2 = iIchimoku(Symbol(), 0, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_KIJUNSEN, aux_shift+1);
   ssA2 = iIchimoku(Symbol(), 0, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_SENKOUSPANA, aux_shift+1);
   ssB2 = iIchimoku(Symbol(), 0, aux_tenkan_sen, aux_kijun_sen, aux_senkou_span, MODE_SENKOUSPANB, aux_shift+1);
   close2=iClose(Symbol(),0,aux_shift+1);

   if(ssA1 >= ssB1) kt1 = ssA1;
   else kt1 = ssB1;

   if(ssA1 <= ssB1) kb1 = ssA1;
   else kb1 = ssB1;

   if(ssA2 >= ssB2) kt2 = ssA2;
   else kt2 = ssB2;

   if(ssA2 <= ssB2) kb2 = ssA2;
   else kb2 = ssB2;

   if((ts1>ks1 && ts2<ks2 && ks1>kt1) || (close1>ks1 && close2<ks2 && ks1>kt1) || (close1>kt1 && close2<kt2))
     {
      aux=1;
     }

   if((ts1<ks1 && ts2>ks2 && ts1<kb1) || (close1<ks1 && close2>ks2 && ks1<kb1) || (close1<kb1 && close2>kb2))
     {
      aux=2;
     }

   int rsi_period=14;
   int macd_signal_period1=12;
   int macd_signal_period2=26;
   int macd_signal_period3=9;

   int osma_fast_ema=12;
   int osma_slow_ema=26;
   int osma_signal_sma=9;

   double rsi=iRSI(Symbol(),0,14,PRICE_CLOSE,aux_shift);
   double macd1 = iMACD(Symbol(), 0, macd_signal_period1, macd_signal_period2, macd_signal_period3, PRICE_CLOSE, MODE_SIGNAL, aux_shift);
   double macd2 = iMACD(Symbol(), 0, macd_signal_period1, macd_signal_period2, macd_signal_period3, PRICE_CLOSE, MODE_SIGNAL, aux_shift+2);
   double osma=iOsMA(Symbol(),0,osma_fast_ema,osma_slow_ema,osma_signal_sma,PRICE_CLOSE,aux_shift);

   if(aux==1 && osma>0 && rsi>=40 && macd1<macd2) return(1);
   else if(aux==2 && osma<0 && rsi<=60 && macd1>macd2) return(2);

   int aux4=0;
   scalp1=iCustom(Symbol(),0,"Scalp",18,800,0,12,16711680,0,0,0,2,65535,0,2,0,2,255,0,2,-0.500000,0.500000,0,1);
   if(scalp1>scalp2 && scalp1>0 && scalp2<0) aux4=1;
   if(scalp1>scalp2 && scalp1>0.25 && scalp2 < 0) aux4 = 2;
   if(scalp1 < scalp2 && scalp1 < 0 && scalp2> 0) aux4 = -1;
   if(scalp1<scalp2 && scalp1< -0.25 && scalp2>0) aux4 = -2;

   scalp2=scalp1;

   if(aux4>1) return(1);
   else if(aux4<-1) return(2);

   int kg=2;
   int Slow_MACD= 18;
   int Alfa_min = 2;
   int Alfa_delta= 34;
   int Fast_MACD = 1;

   int j=0;
   int r=60/Period();
   double MA_0=iMA(NULL,0,Slow_MACD*r*kg,0,MODE_SMA,PRICE_OPEN,j);
   double MA_1=iMA(NULL,0,Slow_MACD*r*kg,0,MODE_SMA,PRICE_OPEN,j+1);
   double Alfa=((MA_0-MA_1)/Point)*r;
   double Fast_0=iOsMA(NULL,0,Fast_MACD*r,Slow_MACD*r,Slow_MACD*r,PRICE_OPEN,j);
   double Fast_1=iOsMA(NULL,0,Fast_MACD*r,Slow_MACD*r,Slow_MACD*r,PRICE_OPEN,j+1);
   double Slow_0=iOsMA(NULL,0,(Fast_MACD+slippage)*r,Slow_MACD*r,Slow_MACD*r,PRICE_OPEN,j);
   double Slow_1=iOsMA(NULL,0,(Fast_MACD+slippage)*r,Slow_MACD*r,Slow_MACD*r,PRICE_OPEN,j+1);

   bool trend_up=0;
   bool trend_dn=0;
   if(Alfa> Alfa_min && Alfa< (Alfa_min+Alfa_delta)) trend_up=1;
   if(Alfa<-Alfa_min && Alfa>-(Alfa_min+Alfa_delta)) trend_dn=1;
   bool longsignal=0;
   bool shortsignal=0;
   if((Fast_0-Slow_0)>0.0 && (Fast_1-Slow_1)<=0.0) longsignal=1;
   if((Fast_0-Slow_0)<0.0 && (Fast_1-Slow_1)>=0.0) shortsignal=1;

   int aux3=aux3();
   if(((trend_up || longsignal) && aux3>0) || aux3>1) return(1);
   else if(((trend_dn || shortsignal) && aux3<0) || aux3<-1) return(2);

   if(aux4>0) return(1);
   else if(aux4<0) return(2);

   fisher1=iCustom(Symbol(),0,"Fisher",200,0,2,255,0,2,0,2,65280,0,2,0,2,255,0,3,12632256,2,1,-0.2500,0.2500,0,1);
   if(fisher1 > 0 && fisher2 < fisher1 && fisher2 < 0) return(1);
   if(fisher1 < 0 && fisher1 < fisher2 && fisher2 > 0) return(2);
   fisher2=fisher1;

   return(0);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int aux3()
  {
   int     TimeFrame1     = 15;
   int     TimeFrame2     = 60;
   int     TimeFrame3     = 240;
   int     TrendPeriod1   = 5;
   int     TrendPeriod2   = 8;
   int     TrendPeriod3   = 13;
   int     TrendPeriod4   = 21;
   int     TrendPeriod5   = 34;

   double MaH11v,MaH41v,MaD11v,MaH1pr1v,MaH4pr1v,MaD1pr1v;
   double MaH12v,MaH42v,MaD12v,MaH1pr2v,MaH4pr2v,MaD1pr2v;
   double MaH13v,MaH43v,MaD13v,MaH1pr3v,MaH4pr3v,MaD1pr3v;
   double MaH14v,MaH44v,MaD14v,MaH1pr4v,MaH4pr4v,MaD1pr4v;
   double MaH15v,MaH45v,MaD15v,MaH1pr5v,MaH4pr5v,MaD1pr5v;

   double u1x5v,u1x8v,u1x13v,u1x21v,u1x34v;
   double u2x5v,u2x8v,u2x13v,u2x21v,u2x34v;
   double u3x5v,u3x8v,u3x13v,u3x21v,u3x34v;
   double u1acv,u2acv,u3acv;

   double d1x5v,d1x8v,d1x13v,d1x21v,d1x34v;
   double d2x5v,d2x8v,d2x13v,d2x21v,d2x34v;
   double d3x5v,d3x8v,d3x13v,d3x21v,d3x34v;
   double d1acv,d2acv,d3acv;

   MaH11v=iMA(NULL,TimeFrame1,TrendPeriod1,0,MODE_SMA,PRICE_CLOSE,0);   MaH1pr1v=iMA(NULL,TimeFrame1,TrendPeriod1,0,MODE_SMA,PRICE_CLOSE,1);
   MaH12v=iMA(NULL,TimeFrame1,TrendPeriod2,0,MODE_SMA,PRICE_CLOSE,0);   MaH1pr2v=iMA(NULL,TimeFrame1,TrendPeriod2,0,MODE_SMA,PRICE_CLOSE,1);
   MaH13v=iMA(NULL,TimeFrame1,TrendPeriod3,0,MODE_SMA,PRICE_CLOSE,0);   MaH1pr3v=iMA(NULL,TimeFrame1,TrendPeriod3,0,MODE_SMA,PRICE_CLOSE,1);
   MaH14v=iMA(NULL,TimeFrame1,TrendPeriod4,0,MODE_SMA,PRICE_CLOSE,0);   MaH1pr4v=iMA(NULL,TimeFrame1,TrendPeriod4,0,MODE_SMA,PRICE_CLOSE,1);
   MaH15v=iMA(NULL,TimeFrame1,TrendPeriod5,0,MODE_SMA,PRICE_CLOSE,0);   MaH1pr5v=iMA(NULL,TimeFrame1,TrendPeriod5,0,MODE_SMA,PRICE_CLOSE,1);

   MaH41v=iMA(NULL,TimeFrame2,TrendPeriod1,0,MODE_SMA,PRICE_CLOSE,0);   MaH4pr1v=iMA(NULL,TimeFrame2,TrendPeriod1,0,MODE_SMA,PRICE_CLOSE,1);
   MaH42v=iMA(NULL,TimeFrame2,TrendPeriod2,0,MODE_SMA,PRICE_CLOSE,0);   MaH4pr2v=iMA(NULL,TimeFrame2,TrendPeriod2,0,MODE_SMA,PRICE_CLOSE,1);
   MaH43v=iMA(NULL,TimeFrame2,TrendPeriod3,0,MODE_SMA,PRICE_CLOSE,0);   MaH4pr3v=iMA(NULL,TimeFrame2,TrendPeriod3,0,MODE_SMA,PRICE_CLOSE,1);
   MaH44v=iMA(NULL,TimeFrame2,TrendPeriod4,0,MODE_SMA,PRICE_CLOSE,0);   MaH4pr4v=iMA(NULL,TimeFrame2,TrendPeriod4,0,MODE_SMA,PRICE_CLOSE,1);
   MaH45v=iMA(NULL,TimeFrame2,TrendPeriod5,0,MODE_SMA,PRICE_CLOSE,0);   MaH4pr5v=iMA(NULL,TimeFrame2,TrendPeriod5,0,MODE_SMA,PRICE_CLOSE,1);

   MaD11v=iMA(NULL,TimeFrame3,TrendPeriod1,0,MODE_SMA,PRICE_CLOSE,0);   MaD1pr1v=iMA(NULL,TimeFrame3,TrendPeriod1,0,MODE_SMA,PRICE_CLOSE,1);
   MaD12v=iMA(NULL,TimeFrame3,TrendPeriod2,0,MODE_SMA,PRICE_CLOSE,0);   MaD1pr2v=iMA(NULL,TimeFrame3,TrendPeriod2,0,MODE_SMA,PRICE_CLOSE,1);
   MaD13v=iMA(NULL,TimeFrame3,TrendPeriod3,0,MODE_SMA,PRICE_CLOSE,0);   MaD1pr3v=iMA(NULL,TimeFrame3,TrendPeriod3,0,MODE_SMA,PRICE_CLOSE,1);
   MaD14v=iMA(NULL,TimeFrame3,TrendPeriod4,0,MODE_SMA,PRICE_CLOSE,0);   MaD1pr4v=iMA(NULL,TimeFrame3,TrendPeriod4,0,MODE_SMA,PRICE_CLOSE,1);
   MaD15v=iMA(NULL,TimeFrame3,TrendPeriod5,0,MODE_SMA,PRICE_CLOSE,0);   MaD1pr5v=iMA(NULL,TimeFrame3,TrendPeriod5,0,MODE_SMA,PRICE_CLOSE,1);

   if(MaH11v < MaH1pr1v) {u1x5v = 0; d1x5v = 1;}
   if(MaH11v > MaH1pr1v) {u1x5v = 1; d1x5v = 0;}
   if(MaH11v == MaH1pr1v){u1x5v = 0; d1x5v = 0;}
   if(MaH41v < MaH4pr1v) {u2x5v = 0; d2x5v = 1;}
   if(MaH41v > MaH4pr1v) {u2x5v = 1; d2x5v = 0;}
   if(MaH41v == MaH4pr1v){u2x5v = 0; d2x5v = 0;}
   if(MaD11v < MaD1pr1v) {u3x5v = 0; d3x5v = 1;}
   if(MaD11v > MaD1pr1v) {u3x5v = 1; d3x5v = 0;}
   if(MaD11v == MaD1pr1v){u3x5v = 0; d3x5v = 0;}

   if(MaH12v < MaH1pr2v) {u1x8v = 0; d1x8v = 1;}
   if(MaH12v > MaH1pr2v) {u1x8v = 1; d1x8v = 0;}
   if(MaH12v == MaH1pr2v){u1x8v = 0; d1x8v = 0;}
   if(MaH42v < MaH4pr2v) {u2x8v = 0; d2x8v = 1;}
   if(MaH42v > MaH4pr2v) {u2x8v = 1; d2x8v = 0;}
   if(MaH42v == MaH4pr2v){u2x8v = 0; d2x8v = 0;}
   if(MaD12v < MaD1pr2v) {u3x8v = 0; d3x8v = 1;}
   if(MaD12v > MaD1pr2v) {u3x8v = 1; d3x8v = 0;}
   if(MaD12v == MaD1pr2v){u3x8v = 0; d3x8v = 0;}

   if(MaH13v < MaH1pr3v) {u1x13v = 0; d1x13v = 1;}
   if(MaH13v > MaH1pr3v) {u1x13v = 1; d1x13v = 0;}
   if(MaH13v == MaH1pr3v){u1x13v = 0; d1x13v = 0;}
   if(MaH43v < MaH4pr3v) {u2x13v = 0; d2x13v = 1;}
   if(MaH43v > MaH4pr3v) {u2x13v = 1; d2x13v = 0;}
   if(MaH43v == MaH4pr3v){u2x13v = 0; d2x13v = 0;}
   if(MaD13v < MaD1pr3v) {u3x13v = 0; d3x13v = 1;}
   if(MaD13v > MaD1pr3v) {u3x13v = 1; d3x13v = 0;}
   if(MaD13v == MaD1pr3v){u3x13v = 0; d3x13v = 0;}

   if(MaH14v < MaH1pr4v) {u1x21v = 0; d1x21v = 1;}
   if(MaH14v > MaH1pr4v) {u1x21v = 1; d1x21v = 0;}
   if(MaH14v == MaH1pr4v){u1x21v = 0; d1x21v = 0;}
   if(MaH44v < MaH4pr4v) {u2x21v = 0; d2x21v = 1;}
   if(MaH44v > MaH4pr4v) {u2x21v = 1; d2x21v = 0;}
   if(MaH44v == MaH4pr4v){u2x21v = 0; d2x21v = 0;}
   if(MaD14v < MaD1pr4v) {u3x21v = 0; d3x21v = 1;}
   if(MaD14v > MaD1pr4v) {u3x21v = 1; d3x21v = 0;}
   if(MaD14v == MaD1pr4v){u3x21v = 0; d3x21v = 0;}

   if(MaH15v < MaH1pr5v) {u1x34v = 0; d1x34v = 1;}
   if(MaH15v > MaH1pr5v) {u1x34v = 1; d1x34v = 0;}
   if(MaH15v == MaH1pr5v){u1x34v = 0; d1x34v = 0;}
   if(MaH45v < MaH4pr5v) {u2x34v = 0; d2x34v = 1;}
   if(MaH45v > MaH4pr5v) {u2x34v = 1; d2x34v = 0;}
   if(MaH45v == MaH4pr5v){u2x34v = 0; d2x34v = 0;}
   if(MaD15v < MaD1pr5v) {u3x34v = 0; d3x34v = 1;}
   if(MaD15v > MaD1pr5v) {u3x34v = 1; d3x34v = 0;}
   if(MaD15v == MaD1pr5v){u3x34v = 0; d3x34v = 0;}

   double  acv  = iAC(NULL, TimeFrame1, 0);
   double  ac1v = iAC(NULL, TimeFrame1, 1);
   double  ac2v = iAC(NULL, TimeFrame1, 2);
   double  ac3v = iAC(NULL, TimeFrame1, 3);

   if((ac1v>ac2v && ac2v>ac3v && acv<0 && acv>ac1v)||(acv>ac1v && ac1v>ac2v && acv>0)) {u1acv = 3; d1acv = 0;}
   if((ac1v<ac2v && ac2v<ac3v && acv>0 && acv<ac1v)||(acv<ac1v && ac1v<ac2v && acv<0)) {u1acv = 0; d1acv = 3;}
   if((((ac1v<ac2v || ac2v<ac3v) && acv<0 && acv>ac1v) || (acv>ac1v && ac1v<ac2v && acv>0))
      || (((ac1v>ac2v || ac2v>ac3v) && acv>0 && acv<ac1v) || (acv<ac1v && ac1v>ac2v && acv<0)))
     {u1acv=0; d1acv=0;}

   double  ac03v = iAC(NULL, TimeFrame3, 0);
   double  ac13v = iAC(NULL, TimeFrame3, 1);
   double  ac23v = iAC(NULL, TimeFrame3, 2);
   double  ac33v = iAC(NULL, TimeFrame3, 3);

   if((ac13v>ac23v && ac23v>ac33v && ac03v<0 && ac03v>ac13v)||(ac03v>ac13v && ac13v>ac23v && ac03v>0)) {u3acv = 3; d3acv = 0;}
   if((ac13v<ac23v && ac23v<ac33v && ac03v>0 && ac03v<ac13v)||(ac03v<ac13v && ac13v<ac23v && ac03v<0)) {u3acv = 0; d3acv = 3;}
   if((((ac13v<ac23v || ac23v<ac33v) && ac03v<0 && ac03v>ac13v) || (ac03v>ac13v && ac13v<ac23v && ac03v>0))
      || (((ac13v>ac23v || ac23v>ac33v) && ac03v>0 && ac03v<ac13v) || (ac03v<ac13v && ac13v>ac23v && ac03v<0)))
     {u3acv=0; d3acv=0;}

   double uitog1v = (u1x5v + u1x8v + u1x13v + u1x21v + u1x34v + u1acv) * 12.5;
   double uitog2v = (u2x5v + u2x8v + u2x13v + u2x21v + u2x34v + u2acv) * 12.5;
   double uitog3v = (u3x5v + u3x8v + u3x13v + u3x21v + u3x34v + u3acv) * 12.5;

   double ditog1v = (d1x5v + d1x8v + d1x13v + d1x21v + d1x34v + d1acv) * 12.5;
   double ditog2v = (d2x5v + d2x8v + d2x13v + d2x21v + d2x34v + d2acv) * 12.5;
   double ditog3v = (d3x5v + d3x8v + d3x13v + d3x21v + d3x34v + d3acv) * 12.5;

   int aux=0;
   if(uitog1v>50  && uitog2v>50  && uitog3v>50) aux=1;
   if(ditog1v>50  && ditog2v>50  && ditog3v>50) aux=-1;
   if(uitog1v>=75 && uitog2v>=75 && uitog3v>=75) aux=2;
   if(ditog1v>=75 && ditog2v>=75 && ditog3v>=75) aux=-2;

   return(aux);
  }
// ------------------------------------------------------------------------------------------------
// Trade
// ------------------------------------------------------------------------------------------------
void Trade()
  {
   double signal=CalculaSignal();

   if(orders>=0 && orders<max_orders)
     {
      if(signal==1)
        {
         OrderSendReliable(Symbol(),OP_BUY,CalcularVolumen(),MarketInfo(Symbol(),MODE_ASK),slippage,GetStopLoss(OP_BUY),GetTakeProfit(OP_BUY),key,magic,0,Blue);
        }

      if(signal==2)
        {
         OrderSendReliable(Symbol(),OP_SELL,CalcularVolumen(),MarketInfo(Symbol(),MODE_BID),slippage,GetStopLoss(OP_SELL),GetTakeProfit(OP_SELL),key,magic,0,Red);
        }
     }

   int op=-1;
   if(direction==1) op = OP_BUY;
   if(direction==2) op = OP_SELL;
   if(orders>0 && GetPfofit(op)>=0)
     {
      for(int k=0; k<OrdersTotal(); k++)
        {
         if(OrderSelect(k,SELECT_BY_POS,MODE_TRADES))
           {
            if(OrderSymbol()==Symbol() && OrderMagicNumber()==magic && OrderType()==op)
              {
               if(direction==1 && signal==2)
                 {
                  OrderCloseReliable(OrderTicket(),OrderLots(),MarketInfo(Symbol(),MODE_BID),slippage,Blue);
                 }
               if(direction==2 && signal==1)
                 {
                  OrderCloseReliable(OrderTicket(),OrderLots(),MarketInfo(Symbol(),MODE_ASK),slippage,Red);
                 }
              }
           }
        }

     }

   if(ts_enable) TrailingStop();
  }
//=============================================================================
//							 OrderSendReliable()
//
//	This is intended to be a drop-in replacement for OrderSend() which, 
//	one hopes, is more resistant to various forms of errors prevalent 
//	with MetaTrader.
//			  
//	RETURN VALUE: 
//
//	Ticket number or -1 under some error conditions.  Check
// final error returned by Metatrader with OrderReliableLastErr().
// This will reset the value from GetLastError(), so in that sense it cannot
// be a total drop-in replacement due to Metatrader flaw. 
//
//	FEATURES:
//
//		 * Re-trying under some error conditions, sleeping a random 
//		   time defined by an exponential probability distribution.
//
//		 * Automatic normalization of Digits
//
//		 * Automatically makes sure that stop levels are more than
//		   the minimum stop distance, as given by the server. If they
//		   are too close, they are adjusted.
//
//		 * Automatically converts stop orders to market orders 
//		   when the stop orders are rejected by the server for 
//		   being to close to market.  NOTE: This intentionally
//       applies only to OP_BUYSTOP and OP_SELLSTOP, 
//       OP_BUYLIMIT and OP_SELLLIMIT are not converted to market
//       orders and so for prices which are too close to current
//       this function is likely to loop a few times and return
//       with the "invalid stops" error message. 
//       Note, the commentary in previous versions erroneously said
//       that limit orders would be converted.  Note also
//       that entering a BUYSTOP or SELLSTOP new order is distinct
//       from setting a stoploss on an outstanding order; use
//       OrderModifyReliable() for that. 
//
//		 * Displays various error messages on the log for debugging.
//
//
//	Matt Kennel, 2006-05-28 and following
//
//=============================================================================
int OrderSendReliable(string symbol,int cmd,double volume,double price,
                      int slippage,double stoploss,double takeprofit,
                      string comment,int magic,datetime expiration=0,
                      color arrow_color=CLR_NONE)
  {

// ------------------------------------------------
// Check basic conditions see if trade is possible. 
// ------------------------------------------------
   OrderReliable_Fname="OrderSendReliable";
   OrderReliablePrint(" attempted "+OrderReliable_CommandString(cmd)+" "+volume+
                      " lots @"+price+" sl:"+stoploss+" tp:"+takeprofit);

   if(IsStopped())
     {
      OrderReliablePrint("error: IsStopped() == true");
      _OR_err=ERR_COMMON_ERROR;
      return(-1);
     }

   int cnt=0;
   while(!IsTradeAllowed() && cnt<retry_attempts)
     {
      OrderReliable_SleepRandomTime(sleep_time,sleep_maximum);
      cnt++;
     }

   if(!IsTradeAllowed())
     {
      OrderReliablePrint("error: no operation possible because IsTradeAllowed()==false, even after retries.");
      _OR_err=ERR_TRADE_CONTEXT_BUSY;

      return(-1);
     }

// Normalize all price / stoploss / takeprofit to the proper # of digits.
   int digits=MarketInfo(symbol,MODE_DIGITS);
   if(digits>0)
     {
      price=NormalizeDouble(price,digits);
      stoploss=NormalizeDouble(stoploss,digits);
      takeprofit=NormalizeDouble(takeprofit,digits);
     }

   if(stoploss!=0)
      OrderReliable_EnsureValidStop(symbol,price,stoploss);

   int err=GetLastError(); // clear the global variable.  
   err=0;
   _OR_err=0;
   bool exit_loop=false;
   bool limit_to_market=false;

// limit/stop order. 
   int ticket=-1;

   if((cmd==OP_BUYSTOP) || (cmd==OP_SELLSTOP) || (cmd==OP_BUYLIMIT) || (cmd==OP_SELLLIMIT))
     {
      cnt=0;
      while(!exit_loop)
        {
         if(IsTradeAllowed())
           {
            ticket=OrderSend(symbol,cmd,volume,price,slippage,stoploss,
                             takeprofit,comment,magic,expiration,arrow_color);
            err=GetLastError();
            _OR_err=err;
           }
         else
           {
            cnt++;
           }

         switch(err)
           {
            case ERR_NO_ERROR:
               exit_loop=true;
               break;

               // retryable errors
            case ERR_SERVER_BUSY:
            case ERR_NO_CONNECTION:
            case ERR_INVALID_PRICE:
            case ERR_OFF_QUOTES:
            case ERR_BROKER_BUSY:
            case ERR_TRADE_CONTEXT_BUSY:
               cnt++;
               break;

            case ERR_PRICE_CHANGED:
            case ERR_REQUOTE:
               RefreshRates();
               continue;   // we can apparently retry immediately according to MT docs.

            case ERR_INVALID_STOPS:
               double servers_min_stop=MarketInfo(symbol,MODE_STOPLEVEL)*MarketInfo(symbol,MODE_POINT);
               if(cmd==OP_BUYSTOP)
                 {
                  // If we are too close to put in a limit/stop order so go to market.
                  if(MathAbs(MarketInfo(symbol,MODE_ASK)-price)<=servers_min_stop)
                     limit_to_market=true;

                 }
               else if(cmd==OP_SELLSTOP)
                 {
                  // If we are too close to put in a limit/stop order so go to market.
                  if(MathAbs(MarketInfo(symbol,MODE_BID)-price)<=servers_min_stop)
                     limit_to_market=true;
                 }
               exit_loop=true;
               break;

            default:
               // an apparently serious error.
               exit_loop=true;
               break;

           }  // end switch 

         if(cnt>retry_attempts)
            exit_loop=true;

         if(exit_loop)
           {
            if(err!=ERR_NO_ERROR)
              {
               OrderReliablePrint("non-retryable error: "+OrderReliableErrTxt(err));
              }
            if(cnt>retry_attempts)
              {
               OrderReliablePrint("retry attempts maxed at "+retry_attempts);
              }
           }

         if(!exit_loop)
           {
            OrderReliablePrint("retryable error ("+cnt+"/"+retry_attempts+
                               "): "+OrderReliableErrTxt(err));
            OrderReliable_SleepRandomTime(sleep_time,sleep_maximum);
            RefreshRates();
           }
        }

      // We have now exited from loop. 
      if(err==ERR_NO_ERROR)
        {
         OrderReliablePrint("apparently successful OP_BUYSTOP or OP_SELLSTOP order placed, details follow.");
         OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES);
         OrderPrint();
         return(ticket); // SUCCESS! 
        }
      if(!limit_to_market)
        {
         OrderReliablePrint("failed to execute stop or limit order after "+cnt+" retries");
         OrderReliablePrint("failed trade: "+OrderReliable_CommandString(cmd)+" "+symbol+
                            "@"+price+" tp@"+takeprofit+" sl@"+stoploss);
         OrderReliablePrint("last error: "+OrderReliableErrTxt(err));
         return(-1);
        }
     }  // end	  

   if(limit_to_market)
     {
      OrderReliablePrint("going from limit order to market order because market is too close.");
      if((cmd==OP_BUYSTOP) || (cmd==OP_BUYLIMIT))
        {
         cmd=OP_BUY;
         price=MarketInfo(symbol,MODE_ASK);
        }
      else if((cmd==OP_SELLSTOP) || (cmd==OP_SELLLIMIT))
        {
         cmd=OP_SELL;
         price=MarketInfo(symbol,MODE_BID);
        }
     }

// we now have a market order.
   err=GetLastError(); // so we clear the global variable.  
   err= 0;
   _OR_err= 0;
   ticket = -1;

   if((cmd==OP_BUY) || (cmd==OP_SELL))
     {
      cnt=0;
      while(!exit_loop)
        {
         if(IsTradeAllowed())
           {
            ticket=OrderSend(symbol,cmd,volume,price,slippage,
                             stoploss,takeprofit,comment,magic,
                             expiration,arrow_color);
            err=GetLastError();
            _OR_err=err;
           }
         else
           {
            cnt++;
           }
         switch(err)
           {
            case ERR_NO_ERROR:
               exit_loop=true;
               break;

            case ERR_SERVER_BUSY:
            case ERR_NO_CONNECTION:
            case ERR_INVALID_PRICE:
            case ERR_OFF_QUOTES:
            case ERR_BROKER_BUSY:
            case ERR_TRADE_CONTEXT_BUSY:
               cnt++; // a retryable error
               break;

            case ERR_PRICE_CHANGED:
            case ERR_REQUOTE:
               RefreshRates();
               continue; // we can apparently retry immediately according to MT docs.

            default:
               // an apparently serious, unretryable error.
               exit_loop=true;
               break;

           }  // end switch 

         if(cnt>retry_attempts)
            exit_loop=true;

         if(!exit_loop)
           {
            OrderReliablePrint("retryable error ("+cnt+"/"+
                               retry_attempts+"): "+OrderReliableErrTxt(err));
            OrderReliable_SleepRandomTime(sleep_time,sleep_maximum);
            RefreshRates();
           }

         if(exit_loop)
           {
            if(err!=ERR_NO_ERROR)
              {
               OrderReliablePrint("non-retryable error: "+OrderReliableErrTxt(err));
              }
            if(cnt>retry_attempts)
              {
               OrderReliablePrint("retry attempts maxed at "+retry_attempts);
              }
           }
        }

      // we have now exited from loop. 
      if(err==ERR_NO_ERROR)
        {
         OrderReliablePrint("apparently successful OP_BUY or OP_SELL order placed, details follow.");
         OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES);
         OrderPrint();
         return(ticket); // SUCCESS! 
        }
      OrderReliablePrint("failed to execute OP_BUY/OP_SELL, after "+cnt+" retries");
      OrderReliablePrint("failed trade: "+OrderReliable_CommandString(cmd)+" "+symbol+
                         "@"+price+" tp@"+takeprofit+" sl@"+stoploss);
      OrderReliablePrint("last error: "+OrderReliableErrTxt(err));
      return(-1);
     }
  }
//=============================================================================
//							 OrderCloseReliable()
//
//	This is intended to be a drop-in replacement for OrderClose() which, 
//	one hopes, is more resistant to various forms of errors prevalent 
//	with MetaTrader.
//			  
//	RETURN VALUE: 
//
//		TRUE if successful, FALSE otherwise
//
//
//	FEATURES:
//
//		 * Re-trying under some error conditions, sleeping a random 
//		   time defined by an exponential probability distribution.
//
//		 * Displays various error messages on the log for debugging.
//
//
//	Derk Wehler, ashwoods155@yahoo.com  	2006-07-19
//
//=============================================================================
bool OrderCloseReliable(int ticket,double lots,double price,
                        int slippage,color arrow_color=CLR_NONE)
  {
   int nOrderType;
   string strSymbol;
   OrderReliable_Fname="OrderCloseReliable";

   OrderReliablePrint(" attempted close of #"+ticket+" price:"+price+
                      " lots:"+lots+" slippage:"+slippage);

// collect details of order so that we can use GetMarketInfo later if needed
   if(!OrderSelect(ticket,SELECT_BY_TICKET))
     {
      _OR_err=GetLastError();
      OrderReliablePrint("error: "+ErrorDescription(_OR_err));
      return(false);
     }
   else
     {
      nOrderType= OrderType();
      strSymbol = OrderSymbol();
     }

   if(nOrderType!=OP_BUY && nOrderType!=OP_SELL)
     {
      _OR_err=ERR_INVALID_TICKET;
      OrderReliablePrint("error: trying to close ticket #"+ticket+", which is "+OrderReliable_CommandString(nOrderType)+", not OP_BUY or OP_SELL");
      return(false);
     }

   if(IsStopped())
     {
      OrderReliablePrint("error: IsStopped() == true");
      return(false);
     }

   int cnt=0;

   int err=GetLastError(); // so we clear the global variable.  
   err=0;
   _OR_err=0;
   bool exit_loop=false;
   cnt=0;
   bool result=false;

   while(!exit_loop)
     {
      if(IsTradeAllowed())
        {
         result=OrderClose(ticket,lots,price,slippage,arrow_color);
         err=GetLastError();
         _OR_err=err;
        }
      else
         cnt++;

      if(result==true)
         exit_loop=true;

      switch(err)
        {
         case ERR_NO_ERROR:
            exit_loop=true;
            break;

         case ERR_SERVER_BUSY:
         case ERR_NO_CONNECTION:
         case ERR_INVALID_PRICE:
         case ERR_OFF_QUOTES:
         case ERR_BROKER_BUSY:
         case ERR_TRADE_CONTEXT_BUSY:
         case ERR_TRADE_TIMEOUT:      // for modify this is a retryable error, I hope. 
            cnt++;    // a retryable error
            break;

         case ERR_PRICE_CHANGED:
         case ERR_REQUOTE:
            continue;    // we can apparently retry immediately according to MT docs.

         default:
            // an apparently serious, unretryable error.
            exit_loop=true;
            break;

        }  // end switch 

      if(cnt>retry_attempts)
         exit_loop=true;

      if(!exit_loop)
        {
         OrderReliablePrint("retryable error ("+cnt+"/"+retry_attempts+
                            "): "+OrderReliableErrTxt(err));
         OrderReliable_SleepRandomTime(sleep_time,sleep_maximum);
         // Added by Paul Hampton-Smith to ensure that price is updated for each retry
         if(nOrderType == OP_BUY)  price = NormalizeDouble(MarketInfo(strSymbol,MODE_BID),MarketInfo(strSymbol,MODE_DIGITS));
         if(nOrderType == OP_SELL) price = NormalizeDouble(MarketInfo(strSymbol,MODE_ASK),MarketInfo(strSymbol,MODE_DIGITS));
        }

      if(exit_loop)
        {
         if((err!=ERR_NO_ERROR) && (err!=ERR_NO_RESULT))
            OrderReliablePrint("non-retryable error: "+OrderReliableErrTxt(err));

         if(cnt>retry_attempts)
            OrderReliablePrint("retry attempts maxed at "+retry_attempts);
        }
     }

// we have now exited from loop. 
   if((result==true) || (err==ERR_NO_ERROR))
     {
      OrderReliablePrint("apparently successful close order, updated trade details follow.");
      OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES);
      OrderPrint();
      return(true); // SUCCESS! 
     }

   OrderReliablePrint("failed to execute close after "+cnt+" retries");
   OrderReliablePrint("failed close: Ticket #"+ticket+", Price: "+
                      price+", Slippage: "+slippage);
   OrderReliablePrint("last error: "+OrderReliableErrTxt(err));

   return(false);
  }
//=============================================================================
//=============================================================================
//								Utility Functions
//=============================================================================
//=============================================================================



int OrderReliableLastErr()
  {
   return (_OR_err);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string OrderReliableErrTxt(int err)
  {
   return ("" + err + ":" + ErrorDescription(err));
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OrderReliablePrint(string s)
  {
// Print to log prepended with stuff;
   if(!(IsTesting() || IsOptimization())) Print(OrderReliable_Fname+" "+OrderReliableVersion+":"+s);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string OrderReliable_CommandString(int cmd)
  {
   if(cmd==OP_BUY)
      return("OP_BUY");

   if(cmd==OP_SELL)
      return("OP_SELL");

   if(cmd==OP_BUYSTOP)
      return("OP_BUYSTOP");

   if(cmd==OP_SELLSTOP)
      return("OP_SELLSTOP");

   if(cmd==OP_BUYLIMIT)
      return("OP_BUYLIMIT");

   if(cmd==OP_SELLLIMIT)
      return("OP_SELLLIMIT");

   return("(CMD==" + cmd + ")");
  }
//=============================================================================
//
//						 OrderReliable_EnsureValidStop()
//
// 	Adjust stop loss so that it is legal.
//
//	Matt Kennel 
//
//=============================================================================
void OrderReliable_EnsureValidStop(string symbol,double price,double &sl)
  {
// Return if no S/L
   if(sl==0)
      return;

   double servers_min_stop=MarketInfo(symbol,MODE_STOPLEVEL)*MarketInfo(symbol,MODE_POINT);

   if(MathAbs(price-sl)<=servers_min_stop)
     {
      // we have to adjust the stop.
      if(price>sl)
         sl=price-servers_min_stop;   // we are long

      else if(price<sl)
         sl=price+servers_min_stop;   // we are short

      else
         OrderReliablePrint("EnsureValidStop: error, passed in price == sl, cannot adjust");

      sl=NormalizeDouble(sl,MarketInfo(symbol,MODE_DIGITS));
     }
  }
//=============================================================================
//
//						 OrderReliable_SleepRandomTime()
//
//	This sleeps a random amount of time defined by an exponential 
//	probability distribution. The mean time, in Seconds is given 
//	in 'mean_time'.
//
//	This is the back-off strategy used by Ethernet.  This will 
//	quantize in tenths of seconds, so don't call this with a too 
//	small a number.  This returns immediately if we are backtesting
//	and does not sleep.
//
//	Matt Kennel mbkennelfx@gmail.com.
//
//=============================================================================
void OrderReliable_SleepRandomTime(double mean_time,double max_time)
  {
   if(IsTesting())
      return;    // return immediately if backtesting.

   double tenths=MathCeil(mean_time/0.1);
   if(tenths<=0)
      return;

   int maxtenths=MathRound(max_time/0.1);
   double p=1.0-1.0/tenths;

   Sleep(100);    // one tenth of a second PREVIOUS VERSIONS WERE STUPID HERE. 

   for(int i=0; i<maxtenths; i++)
     {
      if(MathRand()>p*32768)
         break;

      // MathRand() returns in 0..32767
      Sleep(100);
     }
  }
//+------------------------------------------------------------------+
