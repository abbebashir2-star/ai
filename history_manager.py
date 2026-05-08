import json
import os

HISTORY_FILE = 'market_history.json'

def save_history(data):
    history = load_history()
    for item in data:
        key = f"{item['Country']}_{item['Event']}_{item['Forecast']}"
        history[key] = item
    
    with open(HISTORY_FILE, 'w') as f:
        json.dump(history, f, indent=4)

def load_history():
    if not os.path.exists(HISTORY_FILE):
        return {}
    with open(HISTORY_FILE, 'r') as f:
        try:
            return json.load(f)
        except:
            return {}
