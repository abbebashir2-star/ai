def generate_signal(ticker, current_price, sentiment_data, surprise_index, regime, pitchfork, mtf_bias, session):
    sentiment_score, narrative = sentiment_data
    low, med, up = pitchfork
    
    macro_score = 0
    if abs(surprise_index) > 0.05:
        macro_score = 1 if surprise_index > 0 else -1
        
    range_total = max(up - low, 1e-6)
    pos = (current_price - low) / range_total
    geo_bias = 0
    if pos < 0.1: geo_bias = 1
    elif pos > 0.9: geo_bias = -1
    
    mtf_score = 1 if "ALIGNED BULLISH" in mtf_bias else (-1 if "ALIGNED BEARISH" in mtf_bias else 0)

    p_bull = (0.3 if macro_score > 0 else 0.1) + (0.3 if geo_bias == 1 else 0.1) + (0.2 if sentiment_score > 0.1 else 0.05) + (0.2 if mtf_score == 1 else 0)
    p_bear = (0.3 if macro_score < 0 else 0.1) + (0.3 if geo_bias == -1 else 0.1) + (0.2 if sentiment_score < -0.1 else 0.05) + (0.2 if mtf_score == -1 else 0)
    
    p_neutral = 1.0 - p_bull - p_bear
    if p_neutral < 0: p_neutral = 0
    
    total_p = p_bull + p_bear + p_neutral
    p_bull, p_bear, p_neutral = p_bull/total_p, p_bear/total_p, p_neutral/total_p

    total_score = (macro_score * 0.3) + (sentiment_score * 0.2) + (geo_bias * 0.3) + (mtf_score * 0.2)
    confidence = min(abs(total_score) * 100, 100)
    
    signal = "WAIT"
    if p_bull > 0.6 and total_score > 0.2: signal = "BUY"
    elif p_bear > 0.6 and total_score < -0.2: signal = "SELL"
    
    reasoning = ""
    if "DIVERGENT" in mtf_bias and abs(total_score) < 0.5:
        signal = "WAIT"
        reasoning = "MTF Divergence detected."
    elif p_neutral > 0.5:
        signal = "WAIT"
        reasoning = "Market in equilibrium."
    elif abs(macro_score - geo_bias) > 1.5:
        signal = "WAIT"
        reasoning = "Institutional Conflict (Trap risk)."
    else:
        reasoning = f"Institutional consensus indicates {signal}."

    stages = [
        f"[Macro] Surprise: {surprise_index:.2f}. Narrative: {narrative}.",
        f"[Structural] MTF: {mtf_bias}. Session: {session}.",
        f"[Probabilities] Bull: {p_bull:.1%}, Bear: {p_bear:.1%}"
    ]
    
    return {
        "signal": signal,
        "confidence": f"{confidence:.1f}%",
        "probabilities": {"Bull": p_bull, "Bear": p_bear, "Neutral": p_neutral},
        "stages": stages,
        "reasoning": reasoning,
        "narrative": narrative,
        "regime": regime
    }
