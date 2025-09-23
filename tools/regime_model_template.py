"""
Template utility to rebuild models/regime_signals.json from external analytics.
Fill in the placeholders with your ML or LLM pipeline.
"""

import datetime as dt
import json
import random
from pathlib import Path

OUTPUT_PATH = Path(__file__).resolve().parents[1] / "models" / "regime_signals.json"

SYMBOLS = [
    "EURUSD",
    "GBPUSD",
    "USDJPY",
    "XAUUSD",
]

def load_custom_features(symbol: str) -> dict:
    """Stub: replace with feature engineering / model inference."""
    random.seed(symbol)
    return {
        "trend": random.uniform(0.2, 0.5),
        "micro": random.uniform(0.2, 0.4),
        "reversion": random.uniform(0.1, 0.3),
        "breakout": random.uniform(0.15, 0.35),
        "bias": random.uniform(-0.2, 0.2),
        "risk_multiplier": random.uniform(0.8, 1.4),
        "llm_bias": random.uniform(-0.1, 0.15),
        "regime": random.choice([
            "trending",
            "mean_reversion",
            "volatile",
            "breakout",
        ]),
    }

def normalize_weights(weights: dict) -> dict:
    total = sum(weights.values())
    if total <= 0:
        return {k: 1.0 / len(weights) for k in weights}
    return {k: round(v / total, 3) for k, v in weights.items()}

def build_payload() -> dict:
    payload = {
        "updated": dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
        "default": {
            "bias": 0.0,
            "risk_multiplier": 1.0,
            "regime": "balanced",
            "weights": {
                "trend": 0.35,
                "micro": 0.25,
                "reversion": 0.20,
                "breakout": 0.20,
            },
        },
        "globals": {
            "sentiment_bias": 0.0,
            "risk_multiplier": 1.0,
            "risk_cap": 1.5,
            "news_block_minutes": 35,
        },
        "symbols": {},
    }
    for symbol in SYMBOLS:
        features = load_custom_features(symbol)
        weights = normalize_weights(
            {
                "trend": features["trend"],
                "micro": features["micro"],
                "reversion": features["reversion"],
                "breakout": features["breakout"],
            }
        )
        payload["symbols"][symbol] = {
            "bias": round(features["bias"], 3),
            "risk_multiplier": round(features["risk_multiplier"], 3),
            "regime": features["regime"],
            "llm_bias": round(features["llm_bias"], 3),
            "weights": weights,
        }
    return payload

def main() -> None:
    payload = build_payload()
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(payload, indent=2))
    print(f"Updated model file => {OUTPUT_PATH}")

if __name__ == "__main__":
    main()
