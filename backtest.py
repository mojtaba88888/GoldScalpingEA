import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import yfinance as yf
from typing import Dict, List, Tuple
import warnings
warnings.filterwarnings('ignore')

class GoldScalpingBacktest:
    """
    Gold Scalping EA Backtester
    Price Action + Volume Strategy
    """
    
    def __init__(self, symbol='GC=F', start_date='2016-09-05', end_date='2024-09-05',
                 lot_size=0.1, tp_pips=15, sl_pips=8, timeframe='5min'):
        """Initialize backtester"""
        self.symbol = symbol
        self.start_date = start_date
        self.end_date = end_date
        self.lot_size = lot_size
        self.tp_pips = tp_pips
        self.sl_pips = sl_pips
        self.timeframe = timeframe
        self.data = None
        self.signals = []
        self.trades = []
        self.equity = 10000  # Starting equity
        self.initial_equity = 10000
        
    def download_data(self):
        """Download historical OHLCV data"""
        print(f"📥 Downloading {self.symbol} data from {self.start_date} to {self.end_date}...")
        
        try:
            # Download daily data first
            data = yf.download(self.symbol, start=self.start_date, end=self.end_date, 
                             progress=False, interval='1d')
            
            if len(data) == 0:
                print(f"❌ No data found for {self.symbol}")
                return False
            
            # Reset index
            data = data.reset_index()
            data.columns = ['Date', 'Open', 'High', 'Low', 'Close', 'Adj Close', 'Volume']
            
            # Add technical indicators
            self.add_indicators(data)
            
            self.data = data
            print(f"✅ Downloaded {len(data)} candles")
            return True
            
        except Exception as e:
            print(f"❌ Error downloading data: {e}")
            return False
    
    def add_indicators(self, df):
        """Add technical indicators"""
        # Volume Moving Average
        df['Volume_MA'] = df['Volume'].rolling(window=20).mean()
        
        # RSI
        delta = df['Close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
        rs = gain / loss
        df['RSI'] = 100 - (100 / (1 + rs))
        
        # ATR (Average True Range)
        df['TR'] = np.maximum(
            df['High'] - df['Low'],
            np.maximum(
                abs(df['High'] - df['Close'].shift()),
                abs(df['Low'] - df['Close'].shift())
            )
        )
        df['ATR'] = df['TR'].rolling(window=14).mean()
        
        # Bollinger Bands
        df['SMA'] = df['Close'].rolling(window=20).mean()
        df['STD'] = df['Close'].rolling(window=20).std()
        df['BB_Upper'] = df['SMA'] + (df['STD'] * 2)
        df['BB_Lower'] = df['SMA'] - (df['STD'] * 2)
    
    def detect_pin_bar(self, row, prev_row, threshold=0.6):
        """Detect Pin Bar pattern"""
        body_size = abs(row['Close'] - row['Open'])
        total_size = row['High'] - row['Low']
        
        if total_size == 0:
            return 0
        
        lower_wick = min(row['Open'], row['Close']) - row['Low']
        upper_wick = row['High'] - max(row['Open'], row['Close'])
        
        # Pin Bar Buy (Lower Wick)
        if (lower_wick / total_size) > threshold and (body_size / total_size) < (1 - threshold):
            if lower_wick > upper_wick:
                return 1
        
        # Pin Bar Sell (Upper Wick)
        if (upper_wick / total_size) > threshold and (body_size / total_size) < (1 - threshold):
            if upper_wick > lower_wick:
                return -1
        
        return 0
    
    def detect_engulfing(self, row, prev_row, threshold=0.8):
        """Detect Engulfing pattern"""
        prev_body = abs(prev_row['Close'] - prev_row['Open'])
        curr_body = abs(row['Close'] - row['Open'])
        
        if prev_body == 0:
            return 0
        
        engulfing_ratio = curr_body / prev_body
        
        # Bullish Engulfing
        if (row['Close'] > prev_row['Open'] and 
            row['Open'] < prev_row['Close'] and 
            row['Open'] < prev_row['Low'] and
            engulfing_ratio > threshold):
            return 2
        
        # Bearish Engulfing
        if (row['Close'] < prev_row['Open'] and 
            row['Open'] > prev_row['Close'] and 
            row['Open'] > prev_row['High'] and
            engulfing_ratio > threshold):
            return -2
        
        return 0
    
    def check_volume_confirmation(self, idx, threshold=1.5):
        """Check if volume confirms the signal"""
        if idx < 20 or pd.isna(self.data.loc[idx, 'Volume_MA']):
            return False
        
        current_vol = self.data.loc[idx, 'Volume']
        avg_vol = self.data.loc[idx, 'Volume_MA']
        
        return current_vol > avg_vol * threshold
    
    def generate_signals(self):
        """Generate trading signals"""
        print("📊 Generating signals...")
        
        for idx in range(2, len(self.data)):
            row = self.data.iloc[idx]
            prev_row = self.data.iloc[idx - 1]
            
            # Skip if no volume data
            if pd.isna(row['Volume_MA']):
                continue
            
            # Check patterns
            pin_bar = self.detect_pin_bar(row, prev_row)
            engulfing = self.detect_engulfing(row, prev_row)
            volume_ok = self.check_volume_confirmation(idx)
            
            signal = None
            strength = 0
            reason = ""
            
            # Buy signals
            if pin_bar == 1 and volume_ok:
                signal = 1
                strength = 0.95
                reason = "Pin Bar + Volume"
            elif engulfing == 2 and volume_ok:
                signal = 1
                strength = 0.90
                reason = "Bullish Engulfing + Volume"
            
            # Sell signals
            elif pin_bar == -1 and volume_ok:
                signal = -1
                strength = 0.95
                reason = "Pin Bar + Volume"
            elif engulfing == -2 and volume_ok:
                signal = -1
                strength = 0.90
                reason = "Bearish Engulfing + Volume"
            
            if signal:
                self.signals.append({
                    'Date': row['Date'],
                    'Index': idx,
                    'Signal': signal,
                    'Price': row['Close'],
                    'Strength': strength,
                    'Reason': reason
                })
        
        print(f"✅ Generated {len(self.signals)} signals")
    
    def execute_trades(self):
        """Execute trades based on signals"""
        print("💰 Executing trades...")
        
        position = None
        trade_count = 0
        
        for signal in self.signals:
            idx = signal['Index']
            signal_price = signal['Price']
            
            # Close existing position if opposite signal
            if position and position['Signal'] != signal['Signal']:
                exit_price = self.data.iloc[idx]['Close']
                profit = (exit_price - position['Entry_Price']) * position['Signal'] * self.lot_size * 100
                
                self.trades.append({
                    'Entry_Date': position['Entry_Date'],
                    'Entry_Price': position['Entry_Price'],
                    'Exit_Date': signal['Date'],
                    'Exit_Price': exit_price,
                    'Signal': position['Signal'],
                    'Profit': profit,
                    'Profit_Pips': abs(exit_price - position['Entry_Price']) * signal['Signal'],
                    'Reason': f"Closed: {signal['Reason']}"
                })
                
                self.equity += profit
                position = None
                trade_count += 1
            
            # Enter new position if no open position
            if not position and trade_count < 100:  # Limit trades for backtest
                position = {
                    'Entry_Date': signal['Date'],
                    'Entry_Price': signal_price,
                    'Signal': signal['Signal'],
                    'TP': signal_price + (self.tp_pips * 0.01 * signal['Signal']),
                    'SL': signal_price - (self.sl_pips * 0.01 * signal['Signal'])
                }
                
                # Check for TP/SL in next 5 candles
                hit_tp = False
                hit_sl = False
                
                for i in range(idx + 1, min(idx + 6, len(self.data))):
                    high = self.data.iloc[i]['High']
                    low = self.data.iloc[i]['Low']
                    
                    if signal['Signal'] == 1:
                        if high >= position['TP']:
                            hit_tp = True
                            exit_price = position['TP']
                            exit_date = self.data.iloc[i]['Date']
                            break
                        elif low <= position['SL']:
                            hit_sl = True
                            exit_price = position['SL']
                            exit_date = self.data.iloc[i]['Date']
                            break
                    else:
                        if low <= position['TP']:
                            hit_tp = True
                            exit_price = position['TP']
                            exit_date = self.data.iloc[i]['Date']
                            break
                        elif high >= position['SL']:
                            hit_sl = True
                            exit_price = position['SL']
                            exit_date = self.data.iloc[i]['Date']
                            break
                
                # If TP or SL hit
                if hit_tp or hit_sl:
                    profit = (exit_price - position['Entry_Price']) * signal['Signal'] * self.lot_size * 100
                    
                    self.trades.append({
                        'Entry_Date': position['Entry_Date'],
                        'Entry_Price': position['Entry_Price'],
                        'Exit_Date': exit_date,
                        'Exit_Price': exit_price,
                        'Signal': signal['Signal'],
                        'Profit': profit,
                        'Profit_Pips': abs(exit_price - position['Entry_Price']) * signal['Signal'],
                        'Reason': 'TP Hit' if hit_tp else 'SL Hit'
                    })
                    
                    self.equity += profit
                    position = None
                    trade_count += 1
        
        print(f"✅ Executed {trade_count} trades")
    
    def calculate_statistics(self):
        """Calculate trading statistics"""
        if not self.trades:
            print("❌ No trades executed")
            return None
        
        trades_df = pd.DataFrame(self.trades)
        
        # Basic statistics
        total_trades = len(trades_df)
        winning_trades = len(trades_df[trades_df['Profit'] > 0])
        losing_trades = len(trades_df[trades_df['Profit'] <= 0])
        win_rate = (winning_trades / total_trades * 100) if total_trades > 0 else 0
        
        total_profit = trades_df['Profit'].sum()
        avg_profit = trades_df['Profit'].mean()
        max_profit = trades_df['Profit'].max()
        max_loss = trades_df['Profit'].min()
        
        # Risk/Reward
        avg_win = trades_df[trades_df['Profit'] > 0]['Profit'].mean() if winning_trades > 0 else 0
        avg_loss = abs(trades_df[trades_df['Profit'] <= 0]['Profit'].mean()) if losing_trades > 0 else 0
        profit_factor = (avg_win * winning_trades) / (avg_loss * losing_trades) if losing_trades > 0 else 0
        
        # ROI
        roi = (self.equity - self.initial_equity) / self.initial_equity * 100
        
        # Monthly statistics
        trades_df['Entry_Date'] = pd.to_datetime(trades_df['Entry_Date'])
        trades_df['Month'] = trades_df['Entry_Date'].dt.to_period('M')
        monthly_profit = trades_df.groupby('Month')['Profit'].sum()
        monthly_trades = trades_df.groupby('Month').size()
        
        stats = {
            'Total_Trades': total_trades,
            'Winning_Trades': winning_trades,
            'Losing_Trades': losing_trades,
            'Win_Rate_%': round(win_rate, 2),
            'Total_Profit_$': round(total_profit, 2),
            'Average_Profit_$': round(avg_profit, 2),
            'Max_Profit_$': round(max_profit, 2),
            'Max_Loss_$': round(max_loss, 2),
            'Avg_Win_$': round(avg_win, 2),
            'Avg_Loss_$': round(avg_loss, 2),
            'Profit_Factor': round(profit_factor, 2),
            'ROI_%': round(roi, 2),
            'Final_Equity_$': round(self.equity, 2),
            'Monthly_Profit': monthly_profit.to_dict(),
            'Monthly_Trades': monthly_trades.to_dict()
        }
        
        return stats
    
    def run_backtest(self):
        """Run complete backtest"""
        print("🚀 Starting Backtest...")
        print("=" * 60)
        
        # Download data
        if not self.download_data():
            return False
        
        # Generate signals
        self.generate_signals()
        
        # Execute trades
        self.execute_trades()
        
        # Calculate statistics
        stats = self.calculate_statistics()
        
        return stats
    
    def print_results(self, stats):
        """Print backtest results"""
        print("\n" + "=" * 60)
        print("📊 BACKTEST RESULTS")
        print("=" * 60)
        
        print(f"\n💼 Trade Summary:")
        print(f"  Total Trades: {stats['Total_Trades']}")
        print(f"  Winning: {stats['Winning_Trades']} | Losing: {stats['Losing_Trades']}")
        print(f"  Win Rate: {stats['Win_Rate_%']}%")
        
        print(f"\n💰 Profit/Loss:")
        print(f"  Total Profit: ${stats['Total_Profit_$']:,.2f}")
        print(f"  Average Trade: ${stats['Average_Profit_$']:,.2f}")
        print(f"  Max Win: ${stats['Max_Profit_$']:,.2f}")
        print(f"  Max Loss: ${stats['Max_Loss_$']:,.2f}")
        
        print(f"\n📈 Risk/Reward:")
        print(f"  Avg Win: ${stats['Avg_Win_$']:,.2f}")
        print(f"  Avg Loss: ${stats['Avg_Loss_$']:,.2f}")
        print(f"  Profit Factor: {stats['Profit_Factor']}")
        
        print(f"\n📊 Performance:")
        print(f"  ROI: {stats['ROI_%']}%")
        print(f"  Initial Equity: ${self.initial_equity:,.2f}")
        print(f"  Final Equity: ${stats['Final_Equity_$']:,.2f}")
        
        print(f"\n📅 Monthly Breakdown:")
        print(f"{'Month':<12} {'Profit':<15} {'Trades':<10}")
        print("-" * 37)
        
        for month, profit in stats['Monthly_Profit'].items():
            trades = stats['Monthly_Trades'][month]
            print(f"{str(month):<12} ${profit:>13,.2f} {trades:>9}")
        
        print("\n" + "=" * 60)


def main():
    """Main execution"""
    
    # Initialize backtester
    bt = GoldScalpingBacktest(
        symbol='GC=F',  # Gold futures
        start_date='2016-09-05',
        end_date='2024-09-05',
        lot_size=0.1,
        tp_pips=15,
        sl_pips=8,
        timeframe='1d'
    )
    
    # Run backtest
    stats = bt.run_backtest()
    
    # Print results
    if stats:
        bt.print_results(stats)
    else:
        print("❌ Backtest failed!")


if __name__ == '__main__':
    main()
