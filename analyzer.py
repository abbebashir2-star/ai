from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer
import pandas as pd
import numpy as np
import re

def analyze_sentiment(news_list):
    analyzer = SentimentIntensityAnalyzer()
    financial_lexicon = {
        'bullish': 2.0, 'bearish': -2.0, 'hawkish': 1.5, 'dovish': -1.5,
        'soaring': 1.5, 'plummeting': -1.5, 'surge': 1.0, 'recession': -2.0,
        'growth': 1.0, 'inflation': -0.5, 'tightening': -0.8, 'easing': 0.8,
        'pivot': 1.2, 'soft landing': 1.0, 'higher for longer': -1.2,
        'liquidity crunch': -2.0, 'quantitative easing': 1.5
    }
    analyzer.lexicon.update(financial_lexicon)
    scores = []
    narratives = []
    narrative_keywords = {
        "Soft Landing": ["soft landing", "disinflation", "resilient"],
        "Hard Landing/Recession": ["recession", "contraction", "hard landing"],
        "Higher for Longer": ["higher for longer", "sticky inflation", "restrictive"],
        "Pivot/Easing": ["pivot", "rate cuts", "easing", "dovish"]
    }
    for news in news_list:
        content = news.get('content', {})
        if not content: continue
        title = content.get('title', '').lower()
        summary = (content.get('summary', '') or '').lower()
        text = f"{title}. {summary}"
        scores.append(analyzer.polarity_scores(text)['compound'])
        for name, keywords in narrative_keywords.items():
            if any(k in text for k in keywords): narratives.append(name)
    main_narrative = max(set(narratives), key=narratives.count) if narratives else "Neutral/Data Dependent"
    sentiment_score = sum(scores)/len(scores) if scores else 0
    return sentiment_score, main_narrative

def detect_regime(target_df, dxy_df, yield_df):
    try:
        combined = pd.concat([target_df['Close'], dxy_df['Close'], yield_df['Close']], axis=1).dropna()
        if combined.empty or len(combined) < 20: return "Neutral/Standard Regime (Insufficient Data)"
        combined.columns = ['Target', 'DXY', 'Yield']
        corrs = combined['Target'].rolling(20).corr(combined['DXY'])
        corr_val = corrs.iloc[-1] if not corrs.isna().all() else 0
        yield_change = combined['Yield'].pct_change(10).iloc[-1]
        if corr_val < -0.5 and yield_change > 0: return "Inflationary/Hawkish Regime"
        elif corr_val > 0.3: return "Crisis/Risk-Off Regime"
        elif yield_change < -0.05: return "Liquidity Expansion/Dovish Regime"
        else: return "Neutral/Standard Regime"
    except Exception as e: return f"Neutral Regime (Fallback due to: {e})"

def parse_value(val_str):
    if not val_str: return None
    clean = re.sub(r'[^\d.-]', '', val_str)
    try: return float(clean)
    except: return None

def calculate_surprise_index(events):
    surprises = []
    for ev in events:
        act, fct = parse_value(ev.get('Actual')), parse_value(ev.get('Forecast'))
        if act is not None and fct is not None and fct != 0:
            mult = -1 if "Unemployment" in ev['Event'] else 1
            surprises.append(mult * (act - fct) / abs(fct))
    return sum(surprises)/len(surprises) if surprises else 0

def find_pivots(df):
    df = df.copy()
    df['low_shift'] = df['Low'].shift(1)
    df['low_shift_post'] = df['Low'].shift(-1)
    df['high_shift'] = df['High'].shift(1)
    df['high_shift_post'] = df['High'].shift(-1)
    lows = df[(df['Low'] < df['low_shift']) & (df['Low'] < df['low_shift_post'])]
    highs = df[(df['High'] > df['high_shift']) & (df['High'] > df['high_shift_post'])]
    combined = pd.concat([lows, highs]).sort_index()
    if len(combined) < 3: return (df.index[0], df['Low'].iloc[0]), (df.index[len(df)//2], df['High'].iloc[len(df)//2]), (df.index[-1], df['Low'].iloc[-1])
    last_3 = combined.tail(3)
    p0 = (last_3.index[0], last_3['Low'].iloc[0] if last_3.index[0] in lows.index else last_3['High'].iloc[0])
    p1 = (last_3.index[1], last_3['Low'].iloc[1] if last_3.index[1] in lows.index else last_3['High'].iloc[1])
    p2 = (last_3.index[2], last_3['Low'].iloc[2] if last_3.index[2] in lows.index else last_3['High'].iloc[2])
    return p0, p1, p2

def calculate_pitchfork(df, p0, p1, p2):
    x0, y0 = df.index.get_loc(p0[0]), p0[1]
    x1, y1 = df.index.get_loc(p1[0]), p1[1]
    x2, y2 = df.index.get_loc(p2[0]), p2[1]
    mid_x, mid_y = (x1 + x2) / 2, (y1 + y2) / 2
    slope = (mid_y - y0) / (mid_x - x0)
    curr_x = len(df) - 1
    med, up, low = y0 + slope*(curr_x-x0), y1 + slope*(curr_x-x1), y2 + slope*(curr_x-x2)
    if up < low: up, low = low, up
    return low, med, up

def calculate_mtf_bias(daily_df, weekly_df):
    try:
        w_sma = weekly_df['Close'].rolling(10).mean().iloc[-1]
        w_bias = 1 if weekly_df['Close'].iloc[-1] > w_sma else -1
        d_sma = daily_df['Close'].rolling(50).mean().iloc[-1]
        d_bias = 1 if daily_df['Close'].iloc[-1] > d_sma else -1
        if w_bias == d_bias: return "ALIGNED " + ("BULLISH" if w_bias == 1 else "BEARISH")
        return f"DIVERGENT (W: {'BULL' if w_bias==1 else 'BEAR'}, D: {'BULL' if d_bias==1 else 'BEAR'})"
    except: return "NEUTRAL/UNKNOWN"

def get_current_session():
    import datetime
    hour = datetime.datetime.now(datetime.UTC).hour
    if 0 <= hour < 8: return "Asian"
    elif 8 <= hour < 12: return "London"
    elif 12 <= hour < 16: return "London/NY Overlap"
    elif 16 <= hour < 21: return "New York"
    else: return "US/Asian Transition"

def generate_shape(lower, median, upper, current_price):
    range_total = max(upper - lower, 1e-6)
    pos = (current_price - lower) / range_total
    lines = [
        f"Upper Channel: {upper:.2f}  |--- {'@ (OUTSIDE)' if pos > 1.1 else ''}",
        f"               {(upper+median)/2:.2f}  |    {'<-- Current Price' if 0.75 <= pos < 1.1 else ''}",
        f"Median Line:   {median:.2f}  |--- {'<-- Current Price' if 0.25 <= pos < 0.75 else ''}",
        f"               {(median+lower)/2:.2f}  |    {'<-- Current Price' if -0.1 < pos < 0.25 else ''}",
        f"Lower Channel: {lower:.2f}  |--- {'@ (OUTSIDE)' if pos < -0.1 else ''}"
    ]
    return "\n".join(lines)
File 4: data_fetcher.py
import yfinance as yf
import pandas as pd
import requests
from bs4 import BeautifulSoup
import history_manager

def fetch_market_data(ticker_symbol, period="1y", interval="1d"):
    ticker = yf.Ticker(ticker_symbol)
    return ticker.history(period=period, interval=interval)

def fetch_weekly_data(ticker_symbol):
    ticker = yf.Ticker(ticker_symbol)
    return ticker.history(period="2y", interval="1wk")

def fetch_news(ticker_symbol):
    ticker = yf.Ticker(ticker_symbol)
    return ticker.news

def scrape_calendar():
    url = "https://tradingeconomics.com/calendar"
    headers = {"User-Agent": "Mozilla/5.0"}
    try:
        response = requests.get(url, headers=headers, timeout=10)
        if response.status_code != 200: return []
        soup = BeautifulSoup(response.content, 'html.parser')
        table = soup.find('table', {'id': 'calendar'})
        if not table: return []
        events = []
        for row in table.find_all('tr'):
            if row.get('data-id'):
                cols = row.find_all('td', recursive=False)
                if len(cols) >= 7:
                    event_td = cols[2]
                    event_name = event_td.find('a', class_='calendar-event')
                    event_text = event_name.text.strip() if event_name else event_td.text.strip()
                    actual, previous, forecast = cols[3].find(id='actual'), cols[4].find(id='previous'), cols[6].find(id='forecast')
                    event = {
                        'Country': row.get('data-country', '').upper(),
                        'Event': event_text,
                        'Actual': actual.text.strip() if actual else cols[3].text.strip(),
                        'Previous': previous.text.strip() if previous else cols[4].text.strip(),
                        'Forecast': forecast.text.strip() if forecast else cols[6].text.strip()
                    }
                    events.append(event)
        history_manager.save_history(events)
        return events
    except: return []
