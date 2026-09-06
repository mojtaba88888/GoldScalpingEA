import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import json
import warnings
warnings.filterwarnings('ignore')

class GoldScalpingBacktester:
    """
    Gold Scalping EA Backtester - Version 2
    Simplified and Fixed
    """
    
    def __init__(self, initial_balance=10000, lot_size=0.1, tp_pips=15, sl_pips=8):
        self.initial_balance = initial_balance
        self.balance = initial_balance
        self.lot_size = lot_size
        self.tp_pips = tp_pips
        self.sl_pips = sl_pips
        self.trades = []
        self.signals = []
        
    def create_sample_data(self, days=2920):
        """Create realistic sample data (8 years of daily data)"""
        print("📊 Creating sample data (8 years)...")
        
        dates = pd.date_range(end=datetime.now(), periods=days, freq='D')
        
        # Generate realistic price movement
        np.random.seed(42)
        returns = np.random.normal(0.0001, 0.02, days)
        prices = 1900 * np.exp(np.cumsum(returns))
        
        data = pd.DataFrame({
            'Date': dates,
            'Open': prices + np.random.normal(0, 5, days),
            'High': prices + np.abs(np.random.normal(10, 5, days)),
            'Low': prices - np.abs(np.random.normal(10, 5, days)),
            'Close': prices,
            'Volume': np.random.uniform(1000000, 5000000, days)
        })
        
        # Calculate indicators
        data['Volume_MA'] = data['Volume'].rolling(20, min_periods=1).mean()
        
        print(f"✅ Created {len(data)} candles")
        return data
    
    def detect_pin_bar(self, open_p, high, low, close, threshold=0.6):
        """Detect Pin Bar pattern"""
        body = abs(close - open_p)
        wick = high - low
        
        if wick == 0:
            return 0
        
        lower_wick = min(open_p, close) - low
        upper_wick = high - max(open_p, close)
        
        # Buy signal (Lower wick)
        if lower_wick > wick * threshold and body < wick * (1 - threshold):
            if lower_wick > upper_wick:
                return 1
        
        # Sell signal (Upper wick)
        if upper_wick > wick * threshold and body < wick * (1 - threshold):
            if upper_wick > lower_wick:
                return -1
        
        return 0
    
    def detect_engulfing(self, prev_open, prev_close, prev_high, prev_low,
                        open_p, close, high, low):
        """Detect Engulfing pattern"""
        prev_body = abs(prev_close - prev_open)
        curr_body = abs(close - open_p)
        
        if prev_body == 0:
            return 0
        
        # Bullish Engulfing
        if (close > prev_open and open_p < prev_close and 
            open_p < prev_low and curr_body > prev_body * 0.8):
            return 2
        
        # Bearish Engulfing
        if (close < prev_open and open_p > prev_close and 
            open_p > prev_high and curr_body > prev_body * 0.8):
            return -2
        
        return 0
    
    def check_volume(self, current_vol, avg_vol, threshold=1.5):
        """Check volume confirmation"""
        return current_vol > avg_vol * threshold
    
    def backtest(self, data):
        """Run backtest"""
        print("💰 Running backtest...")
        
        position = None
        trade_id = 0
        
        for idx in range(2, len(data)):
            current = data.iloc[idx]
            previous = data.iloc[idx - 1]
            
            # Skip if no volume data
            if pd.isna(current['Volume_MA']):
                continue
            
            # Detect patterns
            pin_bar = self.detect_pin_bar(
                current['Open'], current['High'], 
                current['Low'], current['Close']
            )
            
            engulfing = self.detect_engulfing(
                previous['Open'], previous['Close'], 
                previous['High'], previous['Low'],
                current['Open'], current['Close'], 
                current['High'], current['Low']
            )
            
            # Check volume
            vol_ok = self.check_volume(
                current['Volume'], 
                current['Volume_MA']
            )
            
            signal = None
            
            # Generate signals
            if pin_bar == 1 and vol_ok:
                signal = 1
            elif engulfing == 2 and vol_ok:
                signal = 1
            elif pin_bar == -1 and vol_ok:
                signal = -1
            elif engulfing == -2 and vol_ok:
                signal = -1
            
            # Close position if opposite signal
            if position and signal and signal != position['side']:
                exit_price = current['Close']
                pnl = (exit_price - position['entry_price']) * position['side'] * self.lot_size * 100
                
                self.trades.append({
                    'entry_date': position['entry_date'],
                    'entry_price': position['entry_price'],
                    'exit_date': current['Date'],
                    'exit_price': exit_price,
                    'side': 'BUY' if position['side'] == 1 else 'SELL',
                    'pnl': pnl
                })
                
                self.balance += pnl
                position = None
            
            # Open new position
            if signal and not position and len(self.trades) < 150:
                position = {
                    'entry_date': current['Date'],
                    'entry_price': current['Close'],
                    'side': signal,
                    'tp': current['Close'] + (self.tp_pips * 0.01 * signal),
                    'sl': current['Close'] - (self.sl_pips * 0.01 * signal)
                }
                
                # Check TP/SL in next candles
                for i in range(idx + 1, min(idx + 6, len(data))):
                    next_candle = data.iloc[i]
                    
                    if signal == 1:  # BUY
                        if next_candle['High'] >= position['tp']:
                            exit_price = position['tp']
                            exit_date = next_candle['Date']
                            pnl = self.tp_pips * self.lot_size
                            hit = True
                            break
                        elif next_candle['Low'] <= position['sl']:
                            exit_price = position['sl']
                            exit_date = next_candle['Date']
                            pnl = -self.sl_pips * self.lot_size
                            hit = True
                            break
                    else:  # SELL
                        if next_candle['Low'] <= position['tp']:
                            exit_price = position['tp']
                            exit_date = next_candle['Date']
                            pnl = self.tp_pips * self.lot_size
                            hit = True
                            break
                        elif next_candle['High'] >= position['sl']:
                            exit_price = position['sl']
                            exit_date = next_candle['Date']
                            pnl = -self.sl_pips * self.lot_size
                            hit = True
                            break
                else:
                    hit = False
                
                if hit:
                    self.trades.append({
                        'entry_date': position['entry_date'],
                        'entry_price': position['entry_price'],
                        'exit_date': exit_date,
                        'exit_price': exit_price,
                        'side': 'BUY' if signal == 1 else 'SELL',
                        'pnl': pnl
                    })
                    
                    self.balance += pnl
                    position = None
        
        print(f"✅ Completed {len(self.trades)} trades")
    
    def calculate_stats(self):
        """Calculate statistics"""
        if not self.trades:
            return None
        
        trades_df = pd.DataFrame(self.trades)
        
        # Basic stats
        total = len(trades_df)
        wins = len(trades_df[trades_df['pnl'] > 0])
        losses = len(trades_df[trades_df['pnl'] <= 0])
        win_rate = (wins / total * 100) if total > 0 else 0
        
        total_pnl = trades_df['pnl'].sum()
        avg_pnl = trades_df['pnl'].mean()
        max_win = trades_df['pnl'].max()
        max_loss = trades_df['pnl'].min()
        
        # Monthly breakdown
        trades_df['entry_date'] = pd.to_datetime(trades_df['entry_date'])
        trades_df['month'] = trades_df['entry_date'].dt.to_period('M')
        
        monthly = trades_df.groupby('month').agg({
            'pnl': 'sum',
            'entry_date': 'count'
        }).rename(columns={'entry_date': 'count'})
        
        roi = (self.balance - self.initial_balance) / self.initial_balance * 100
        
        return {
            'total_trades': total,
            'winning_trades': wins,
            'losing_trades': losses,
            'win_rate_pct': round(win_rate, 2),
            'total_pnl': round(total_pnl, 2),
            'avg_pnl': round(avg_pnl, 2),
            'max_win': round(max_win, 2),
            'max_loss': round(max_loss, 2),
            'roi_pct': round(roi, 2),
            'final_balance': round(self.balance, 2),
            'monthly_stats': monthly.to_dict()
        }
    
    def print_results(self, stats):
        """Print results"""
        print("\n" + "="*60)
        print("📊 BACKTEST RESULTS - 8 YEARS")
        print("="*60)
        
        print(f"\n💼 TRADE SUMMARY:")
        print(f"  Total Trades: {stats['total_trades']}")
        print(f"  Winning: {stats['winning_trades']} | Losing: {stats['losing_trades']}")
        print(f"  Win Rate: {stats['win_rate_pct']}%")
        
        print(f"\n💰 PROFIT/LOSS:")
        print(f"  Total P&L: ${stats['total_pnl']:,.2f}")
        print(f"  Average Trade: ${stats['avg_pnl']:,.2f}")
        print(f"  Best Trade: ${stats['max_win']:,.2f}")
        print(f"  Worst Trade: ${stats['max_loss']:,.2f}")
        
        print(f"\n📈 PERFORMANCE:")
        print(f"  ROI: {stats['roi_pct']}%")
        print(f"  Initial Balance: ${self.initial_balance:,.2f}")
        print(f"  Final Balance: ${stats['final_balance']:,.2f}")
        
        print(f"\n📅 MONTHLY BREAKDOWN:")
        print(f"{'Month':<12} {'Profit':<15} {'Trades':<10}")
        print("-"*37)
        
        pnl_dict = stats['monthly_stats']['pnl']
        count_dict = stats['monthly_stats']['count']
        
        for month in sorted(pnl_dict.keys())[:12]:  # Show last 12 months
            pnl = pnl_dict.get(month, 0)
            count = count_dict.get(month, 0)
            print(f"{str(month):<12} ${pnl:>13,.2f} {int(count):>9}")
        
        print("\n" + "="*60)


def main():
    """Main execution"""
    print("🚀 Gold Scalping EA Backtester v2")
    print("="*60)
    
    # Create backtester
    bt = GoldScalpingBacktester(
        initial_balance=10000,
        lot_size=0.1,
        tp_pips=15,
        sl_pips=8
    )
    
    # Create data
    data = bt.create_sample_data()
    
    # Run backtest
    bt.backtest(data)
    
    # Get stats
    stats = bt.calculate_stats()
    
    if stats:
        bt.print_results(stats)
    else:
        print("❌ No trades generated!")


if __name__ == '__main__':
    main()
