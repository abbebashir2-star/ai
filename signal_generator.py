def generate_signal(ticker, current_price, sentiment_data, surprise_index, regime, pitchfork, mtf_bias, session):
    sentiment_score, narrative = sentiment_data
    low, med, up = pitchfork
    macro_score = 1 if surprise_index > 0.05 else (-1 if surprise_index < -0.05 else 0)
    range_total = max(up - low, 1e-6)
    pos = (current_price - low) / range_total
    geo_bias = 1 if pos < 0.1 else (-1 if pos > 0.9 else 0)
    mtf_score = 1 if "ALIGNED BULLISH" in mtf_bias else (-1 if "ALIGNED BEARISH" in mtf_bias else 0)

    p_bull = (0.3 if macro_score > 0 else 0.1) + (0.3 if geo_bias == 1 else 0.1) + (0.2 if sentiment_score > 0.1 else 0.05) + (0.2 if mtf_score == 1 else 0)
    p_bear = (0.3 if macro_score < 0 else 0.1) + (0.3 if geo_bias == -1 else 0.1) + (0.2 if sentiment_score < -0.1 else 0.05) + (0.2 if mtf_score == -1 else 0)
    p_neu = max(0, 1.0 - p_bull - p_bear)
    tot = p_bull + p_bear + p_neu
    p_bull, p_bear, p_neu = p_bull/tot, p_bear/tot, p_neu/tot

    total_score = (macro_score * 0.3) + (sentiment_score * 0.2) + (geo_bias * 0.3) + (mtf_score * 0.2)
    signal = "WAIT"
    if p_bull > 0.6 and total_score > 0.2: signal = "BUY"
    elif p_bear > 0.6 and total_score < -0.2: signal = "SELL"
    
    reasoning = f"Institutional consensus indicates {signal}."
    if "DIVERGENT" in mtf_bias and abs(total_score) < 0.5: signal, reasoning = "WAIT", "MTF Divergence detected."
    elif p_neu > 0.5: signal, reasoning = "WAIT", "High neutral probability."
    elif abs(macro_score - geo_bias) > 1.5: signal, reasoning = "WAIT", "Institutional Conflict (Trap Risk)."

    return {
        "signal": signal,
        "confidence": f"{min(abs(total_score)*100, 100):.1f}%",
        "probabilities": {"Bull": p_bull, "Bear": p_bear, "Neutral": p_neu},
        "stages": [f"Macro Surprise: {surprise_index:.2f}", f"MTF Bias: {mtf_bias}", f"Regime: {regime}"],
        "reasoning": reasoning, "narrative": narrative, "regime": regime
    }
File 6: history_manager.py
import json, os
HISTORY_FILE = 'market_history.json'
def save_history(data):
    history = load_history()
    for item in data:
        key = f"{item['Country']}_{item['Event']}_{item['Forecast']}"
        history[key] = item
    with open(HISTORY_FILE, 'w') as f: json.dump(history, f, indent=4)
def load_history():
    if not os.path.exists(HISTORY_FILE): return {}
    with open(HISTORY_FILE, 'r') as f:
        try: return json.load(f)
        except: return {}
