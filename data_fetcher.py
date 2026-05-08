import yfinance as yf
import pandas as pd
import requests
from bs4 import BeautifulSoup
import history_manager

def fetch_market_data(ticker_symbol, period="1y", interval="1d"):
    ticker = yf.Ticker(ticker_symbol)
    df = ticker.history(period=period, interval=interval)
    return df

def fetch_weekly_data(ticker_symbol):
    ticker = yf.Ticker(ticker_symbol)
    return ticker.history(period="2y", interval="1wk")

def fetch_news(ticker_symbol):
    ticker = yf.Ticker(ticker_symbol)
    return ticker.news

def scrape_calendar():
    url = "https://tradingeconomics.com/calendar"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
    }
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        if response.status_code != 200:
            return []
        
        soup = BeautifulSoup(response.content, 'html.parser')
        table = soup.find('table', {'id': 'calendar'})
        if not table:
            return []
            
        events = []
        rows = table.find_all('tr')
        for row in rows:
            if row.get('data-id'):
                cols = row.find_all('td', recursive=False)
                if len(cols) >= 7:
                    event_td = cols[2]
                    event_name = event_td.find('a', class_='calendar-event')
                    event_text = event_name.text.strip() if event_name else event_td.text.strip()
                    
                    actual = cols[3].find(id='actual')
                    previous = cols[4].find(id='previous')
                    consensus = cols[5].find(id='consensus')
                    forecast = cols[6].find(id='forecast')

                    event = {
                        'Country': row.get('data-country', '').upper(),
                        'Event': event_text,
                        'Actual': actual.text.strip() if actual else cols[3].text.strip(),
                        'Previous': previous.text.strip() if previous else cols[4].text.strip(),
                        'Consensus': consensus.text.strip() if consensus else cols[5].text.strip(),
                        'Forecast': forecast.text.strip() if forecast else cols[6].text.strip()
                    }
                    events.append(event)
        
        history_manager.save_history(events)
        return events
    except Exception as e:
        return []
