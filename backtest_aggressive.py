import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import json

class AggressiveGoldBacktester:
    """
    Aggressive Gold Scalping Backtester
    3-5% Daily Target
    """
    
    def __init__(self, initial_balance=10000, lot_size=0.5, tp_pips=25, sl_pips=5):
        self.initial_balance = initial_balance
        self.balance = initial_balance
        self.lot_size = lot_size
        self.tp_pips = tp_pips
        self.sl_pips = sl_pips
        self.trades = []
        self.daily_results = {}
        
    def create_data(self, days=2920):
        """Create 8 years of data"""
        print("📊 Creating 8 years of simulated data...")
        
        dates = pd.date_range(end=datetime.now(), periods=days, freq='D')
        
        # Realistic gold prices
        np.random.seed(42)
        returns = np.random.normal(0.00015, 0.015, days)
        prices = 1900 * np.exp(np.cumsum(returns))
        
        data = pd.DataFrame({
            'Date': dates,
            'Open': prices + np.random.normal(0, 3, days),
            'High': prices + np.abs(np.random.normal(8, 3, days)),
            'Low': prices - np.abs(np.random.normal(8, 3, days)),
            'Close': prices,
            'Volume': np.random.uniform(1000000, 5000000, days)
        })
        
        # Indicators
        data['Volume_MA'] = data['Volume'].rolling(15, min_periods=1).mean()
        
        return data
    
    def detect_signal(self, row_data):
        """Detect trading signals"""
        if len(row_data) < 2:
            return None
            
        curr = row_data[-1]
        prev = row_data[-2]
        
        # Pin Bar Detection
        body = abs(curr['Close'] - curr['Open'])
        wick = curr['High'] - curr['Low']
        
        if wick > 0:
            lower_wick = min(curr['Open'], curr['Close']) - curr['Low']
            upper_wick = curr['High'] - max(curr['Open'], curr['Close'])
            
            # Pin Bar Buy
            if lower_wick > wick * 0.55 and body < wick * 0.45:
                if lower_wick > upper_wick:
                    return 1
            
            # Pin Bar Sell
            if upper_wick > wick * 0.55 and body < wick * 0.45:
                if upper_wick > lower_wick:
                    return -1
        
        # Engulfing
        prev_body = abs(prev['Close'] - prev['Open'])
        curr_body = abs(curr['Close'] - curr['Open'])
        
        if prev_body > 0:
            # Bullish Engulfing
            if (curr['Close'] > prev['Open'] and curr['Open'] < prev['Close'] and 
                curr['Open'] < prev['Low'] and curr_body > prev_body * 0.75):
                return 1
            
            # Bearish Engulfing
            if (curr['Close'] < prev['Open'] and curr['Open'] > prev['Close'] and 
                curr['Open'] > prev['High'] and curr_body > prev_body * 0.75):
                return -1
        
        return None
    
    def check_volume(self, curr_vol, avg_vol):
        """Check volume confirmation"""
        return curr_vol > avg_vol * 1.3
    
    def backtest(self, data):
        """Run backtest"""
        print("💰 Running aggressive backtest...\n")
        
        position = None
        daily_trades = {}
        
        for idx in range(2, len(data)):
            current_date = data.iloc[idx]['Date']
            date_str = current_date.strftime('%Y-%m-%d')
            
            # Reset daily trades
            if date_str not in daily_trades:
                daily_trades[date_str] = {'trades': 0, 'profit': 0}
            
            # Get recent candles
            recent = data.iloc[max(0, idx-5):idx+1]
            
            # Detect signal
            signal = self.detect_signal([dict(row) for _, row in recent.iterrows()])
            
            # Check volume
            vol_ok = self.check_volume(
                data.iloc[idx]['Volume'],
                data.iloc[idx]['Volume_MA']
            )
            
            if not signal or not vol_ok:
                continue
            
            # Close opposite position
            if position and position['side'] != signal:
                exit_price = data.iloc[idx]['Close']
                pnl = (exit_price - position['entry_price']) * position['side'] * self.lot_size * 100
                
                self.trades.append({
                    'entry_date': position['entry_date'],
                    'entry_price': position['entry_price'],
                    'exit_date': current_date,
                    'exit_price': exit_price,
                    'side': 'BUY' if position['side'] == 1 else 'SELL',
                    'pnl': pnl,
                    'pips': abs(exit_price - position['entry_price']) * 100
                })
                
                self.balance += pnl
                daily_trades[date_str]['trades'] += 1
                daily_trades[date_str]['profit'] += pnl
                position = None
            
            # Open new position (max 8 per day)
            if not position and daily_trades[date_str]['trades'] < 8:
                position = {
                    'entry_date': current_date,
                    'entry_price': data.iloc[idx]['Close'],
                    'side': signal,
                    'tp': data.iloc[idx]['Close'] + (self.tp_pips * 0.01 * signal),
                    'sl': data.iloc[idx]['Close'] - (self.sl_pips * 0.01 * signal)
                }
                
                # Check TP/SL in next candles
                hit = False
                for i in range(idx + 1, min(idx + 6, len(data))):
                    high = data.iloc[i]['High']
                    low = data.iloc[i]['Low']
                    
                    if signal == 1:  # BUY
                        if high >= position['tp']:
                            pnl = self.tp_pips * self.lot_size
                            hit = True
                            break
                        elif low <= position['sl']:
                            pnl = -self.sl_pips * self.lot_size
                            hit = True
                            break
                    else:  # SELL
                        if low <= position['tp']:
                            pnl = self.tp_pips * self.lot_size
                            hit = True
                            break
                        elif high >= position['sl']:
                            pnl = -self.sl_pips * self.lot_size
                            hit = True
                            break
                
                if hit:
                    self.trades.append({
                        'entry_date': position['entry_date'],
                        'entry_price': position['entry_price'],
                        'exit_date': data.iloc[i]['Date'],
                        'exit_price': position['tp'] if pnl > 0 else position['sl'],
                        'side': 'BUY' if signal == 1 else 'SELL',
                        'pnl': pnl,
                        'pips': self.tp_pips if pnl > 0 else -self.sl_pips
                    })
                    
                    self.balance += pnl
                    daily_trades[date_str]['trades'] += 1
                    daily_trades[date_str]['profit'] += pnl
                    position = None
        
        self.daily_results = daily_trades
        print(f"✅ Completed {len(self.trades)} trades\n")
    
    def calculate_stats(self):
        """Calculate statistics"""
        if not self.trades:
            return None
        
        trades = pd.DataFrame(self.trades)
        
        # Basic stats
        total = len(trades)
        wins = len(trades[trades['pnl'] > 0])
        losses = len(trades[trades['pnl'] <= 0])
        win_rate = (wins / total * 100) if total > 0 else 0
        
        total_pnl = trades['pnl'].sum()
        avg_pnl = trades['pnl'].mean()
        max_win = trades['pnl'].max()
        max_loss = trades['pnl'].min()
        
        # Win/Loss stats
        avg_win = trades[trades['pnl'] > 0]['pnl'].mean() if wins > 0 else 0
        avg_loss = abs(trades[trades['pnl'] <= 0]['pnl'].mean()) if losses > 0 else 0
        profit_factor = (avg_win * wins) / (avg_loss * losses) if losses > 0 else 0
        
        # Monthly stats
        trades['entry_date'] = pd.to_datetime(trades['entry_date'])
        trades['month'] = trades['entry_date'].dt.to_period('M')
        monthly = trades.groupby('month').agg({
            'pnl': ['sum', 'count', 'mean']
        })
        
        roi = (self.balance - self.initial_balance) / self.initial_balance * 100
        
        # Daily stats
        daily_profits = [v['profit'] for v in self.daily_results.values()]
        winning_days = len([p for p in daily_profits if p > 0])
        
        return {
            'total_trades': total,
            'winning_trades': wins,
            'losing_trades': losses,
            'win_rate_pct': round(win_rate, 2),
            'total_pnl': round(total_pnl, 2),
            'avg_pnl': round(avg_pnl, 2),
            'max_win': round(max_win, 2),
            'max_loss': round(max_loss, 2),
            'avg_win': round(avg_win, 2),
            'avg_loss': round(avg_loss, 2),
            'profit_factor': round(profit_factor, 2),
            'roi_pct': round(roi, 2),
            'final_balance': round(self.balance, 2),
            'winning_days': winning_days,
            'total_days': len(self.daily_results),
            'monthly_data': monthly.to_dict()
        }
    
    def print_results(self, stats):
        """Print comprehensive results"""
        print("=" * 70)
        print("📊 AGGRESSIVE GOLD SCALPING EA - 8 YEAR BACKTEST RESULTS")
        print("=" * 70)
        
        print(f"\n💼 TRADE STATISTICS:")
        print(f"  Total Trades: {stats['total_trades']}")
        print(f"  Winning Trades: {stats['winning_trades']}")
        print(f"  Losing Trades: {stats['losing_trades']}")
        print(f"  Win Rate: {stats['win_rate_pct']}%")
        
        print(f"\n💰 PROFIT & LOSS:")
        print(f"  Total Profit: ${stats['total_pnl']:,.2f}")
        print(f"  Average Trade: ${stats['avg_pnl']:,.2f}")
        print(f"  Best Trade: ${stats['max_win']:,.2f}")
        print(f"  Worst Trade: ${stats['max_loss']:,.2f}")
        
        print(f"\n📈 RISK/REWARD:")
        print(f"  Average Win: ${stats['avg_win']:,.2f}")
        print(f"  Average Loss: ${stats['avg_loss']:,.2f}")
        print(f"  Profit Factor: {stats['profit_factor']}")
        
        print(f"\n🎯 PERFORMANCE METRICS:")
        print(f"  Initial Balance: ${self.initial_balance:,.2f}")
        print(f"  Final Balance: ${stats['final_balance']:,.2f}")
        print(f"  ROI: {stats['roi_pct']}%")
        print(f"  Winning Days: {stats['winning_days']} / {stats['total_days']}")
        print(f"  Daily Win Rate: {round(stats['winning_days']/stats['total_days']*100, 2)}%")
        
        print(f"\n📅 MONTHLY BREAKDOWN (Last 12 Months):")
        print(f"{'Month':<12} {'Profit':<15} {'Trades':<10} {'Avg/Trade':<12}")
        print("-" * 50)
        
        # Get monthly data
        monthly_dict = stats['monthly_data']['pnl']
        month_keys = sorted(list(monthly_dict['sum'].keys()))[-12:]
        
        total_monthly_profit = 0
        for month in month_keys:
            profit = monthly_dict['sum'].get(month, 0)
            count = int(monthly_dict['count'].get(month, 0))
            avg = monthly_dict['mean'].get(month, 0)
            total_monthly_profit += profit
            print(f"{str(month):<12} ${profit:>13,.2f} {count:>9} ${avg:>10,.2f}")
        
        print("-" * 50)
        print(f"{'12-Month Avg':<12} ${total_monthly_profit/12:>13,.2f}")
        
        print(f"\n💵 DAILY PROFIT ANALYSIS:")
        daily_profits = [v['profit'] for v in self.daily_results.values()]
        print(f"  Average Daily Profit: ${np.mean(daily_profits):,.2f}")
        print(f"  Max Daily Profit: ${np.max(daily_profits):,.2f}")
        print(f"  Min Daily Profit: ${np.min(daily_profits):,.2f}")
        print(f"  Daily Std Dev: ${np.std(daily_profits):,.2f}")
        
        print("\n" + "=" * 70)
        print("✅ BACKTEST COMPLETE")
        print("=" * 70)


def main():
    print("🚀 AGGRESSIVE GOLD SCALPING EA BACKTESTER v2.0")
    print("=" * 70)
    print("Target: 3-5% Daily Profit")
    print("Lot Size: 0.5 | TP: 25 pips | SL: 5 pips")
    print("=" * 70)
    print()
    
    # Create backtester
    bt = AggressiveGoldBacktester(
        initial_balance=10000,
        lot_size=0.5,
        tp_pips=25,
        sl_pips=5
    )
    
    # Create data
    data = bt.create_data(days=2920)
    
    # Run backtest
    bt.backtest(data)
    
    # Calculate stats
    stats = bt.calculate_stats()
    
    if stats:
        bt.print_results(stats)
        
        # Export to JSON
        export_data = {
            'strategy': 'Aggressive Gold Scalping EA',
            'parameters': {
                'initial_balance': bt.initial_balance,
                'lot_size': bt.lot_size,
                'tp_pips': bt.tp_pips,
                'sl_pips': bt.sl_pips
            },
            'results': stats
        }
        
        with open('backtest_results.json', 'w') as f:
            json.dump(export_data, f, indent=2, default=str)
        
        print("\n✅ Results saved to backtest_results.json")
    else:
        print("❌ No trades generated!")


if __name__ == '__main__':
    main()
