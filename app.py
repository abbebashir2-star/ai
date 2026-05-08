import streamlit as st
import data_fetcher
import analyzer
import signal_generator
import datetime
import pandas as pd

st.set_page_config(page_title="Institutional Market Intelligence AI", layout="wide")

st.title("🏛️ Institutional Market Intelligence AI")
st.markdown("Professional-grade analysis for Forex, Gold, and Commodities.")

# --- Sidebar ---
st.sidebar.header("Global Macro Status")
if st.sidebar.button("Refresh All Data"):
    st.cache_data.clear()

@st.cache_data(ttl=3600)
def get_macro_data():
    dxy_df = data_fetcher.fetch_market_data("DX-Y.NYB")
    yield_df = data_fetcher.fetch_market_data("^TNX")
    calendar = data_fetcher.scrape_calendar()
    surprise_index = analyzer.calculate_surprise_index(calendar)
    session = analyzer.get_current_session()
    return dxy_df, yield_df, calendar, surprise_index, session

dxy_df, yield_df, calendar, surprise_index, session = get_macro_data()

st.sidebar.metric("Active Session", session)
st.sidebar.metric("Global Surprise Index", f"{surprise_index:.2f}")

st.sidebar.markdown("---")
st.sidebar.subheader("Recent Economic Releases")
if calendar:
    cal_df = pd.DataFrame(calendar).head(10)
    st.sidebar.table(cal_df[['Country', 'Event', 'Actual', 'Forecast']])

# --- Main Dashboard ---
assets = [
    ("GC=F", "GOLD"),
    ("EURUSD=X", "EUR/USD"),
    ("CL=F", "CRUDE OIL")
]

tabs = st.tabs([name for _, name in assets])

for i, (ticker, name) in enumerate(assets):
    with tabs[i]:
        st.header(f"Asset Intelligence: {name}")
        
        try:
            # Data Fetching
            daily_df = data_fetcher.fetch_market_data(ticker)
            weekly_df = data_fetcher.fetch_weekly_data(ticker)
            news = data_fetcher.fetch_news(ticker)
            current_price = daily_df['Close'].iloc[-1]
            
            # Analysis
            regime = analyzer.detect_regime(daily_df, dxy_df, yield_df)
            sentiment_data = analyzer.analyze_sentiment(news)
            mtf_bias = analyzer.calculate_mtf_bias(daily_df, weekly_df)
            p0, p1, p2 = analyzer.find_pivots(daily_df)
            pitchfork = analyzer.calculate_pitchfork(daily_df, p0, p1, p2)
            shape = analyzer.generate_shape(*pitchfork, current_price)
            
            # Signal
            res = signal_generator.generate_signal(ticker, current_price, sentiment_data, surprise_index, regime, pitchfork, mtf_bias, session)
            
            # UI Layout
            col1, col2, col3 = st.columns(3)
            col1.metric("Current Price", f"{current_price:.2f}")
            col2.metric("Regime", res['regime'])
            col3.metric("Narrative", res['narrative'])
            
            st.subheader("Institutional Analysis")
            for stage in res['stages']:
                st.info(stage)
            
            st.subheader("Geometric Liquidity Channels (Andrews' Pitchfork)")
            st.code(shape)
            
            # Decision Box
            st.markdown("---")
            color = "green" if res['signal'] == "BUY" else ("red" if res['signal'] == "SELL" else "orange")
            st.markdown(f"### FINAL DECISION: <span style='color:{color}'>{res['signal']}</span>", unsafe_allow_html=True)
            st.markdown(f"**Confidence Score:** {res['confidence']}")
            st.write(f"**Reasoning:** {res['reasoning']}")
            
            # Probabilities Chart
            st.subheader("Scenario Probabilities")
            prob_df = pd.DataFrame([res['probabilities']])
            st.bar_chart(prob_df.T)
            
        except Exception as e:
            st.error(f"Error analyzing {name}: {e}")
