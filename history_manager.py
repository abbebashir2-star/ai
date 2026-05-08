import json, os
def save_history(d):
    h = load_history()
    for i in d: h[f"{i['Country']}_{i['Event']}"] = i
    with open('history.json', 'w') as f: json.dump(h, f)
def load_history():
    if not os.path.exists('history.json'): return {}
    with open('history.json', 'r') as f: return json.load(f)
