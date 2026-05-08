import yfinance as yf, requests, history_manager
from bs4 import BeautifulSoup
def fetch_market_data(t, p="1y"): return yf.Ticker(t).history(period=p)
def fetch_weekly_data(t): return yf.Ticker(t).history(period="2y", interval="1wk")
def fetch_news(t): return yf.Ticker(t).news
def scrape_calendar():
    try:
        res = requests.get("https://tradingeconomics.com/calendar", headers={"User-Agent":"Mozilla/5.0"}, timeout=10)
        soup = BeautifulSoup(res.content, 'html.parser')
        evs = []
        for r in soup.find_all('tr'):
            if r.get('data-id'):
                c = r.find_all('td', recursive=False)
                if len(c) >= 7: evs.append({'Country': r.get('data-country',''), 'Event': c[2].text.strip(), 'Actual': c[3].text.strip(), 'Forecast': c[6].text.strip()})
        history_manager.save_history(evs)
        return evs
    except: return []
