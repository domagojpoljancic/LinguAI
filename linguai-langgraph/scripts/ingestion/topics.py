"""
Deterministic topic tagging for vocabulary rows.

Maps headwords / default_text to product topic keys: restaurant, travel, business,
dating, shopping, health, daily, general.
"""

import re
from typing import Optional

# Keyword sets per topic (lowercase). Used for substring/token match.
TOPIC_KEYWORDS: dict[str, list[str]] = {
    "restaurant": ["restaurant", "food", "dining", "menu", "kitchen", "cooking", "recipe", "cafe", "bar", "eat", "meal", "waiter", "bill", "table", "fork", "knife", "spoon", "reservation", "water", "drink"],
    "travel": ["travel", "airport", "hotel", "vacation", "trip", "flight", "directions", "transport", "ticket", "train", "passport", "luggage", "boarding", "flight"],
    "business": ["business", "meeting", "office", "work", "email", "presentation", "negotiation", "deadline", "invoice", "contract", "agenda", "meeting"],
    "dating": ["dating", "romance", "relationship", "love", "flirt", "partner", "date"],
    "shopping": ["shopping", "store", "market", "buy", "price", "clothes", "shop", "discount", "cashier", "receipt"],
    "health": ["health", "doctor", "pharmacy", "hospital", "medicine", "symptoms", "appointment", "symptom"],
    "daily": ["daily", "routine", "everyday", "greetings", "hello", "goodbye", "please", "thank", "sorry", "yes", "no", "basic", "number", "one", "two", "three"],
}
DEFAULT_TOPIC = "general"


def tag_topic(default_text: str) -> str:
    """Return a single topic key for default_text (deterministic)."""
    if not default_text:
        return DEFAULT_TOPIC
    lower = default_text.lower().strip()
    tokens = set(re.split(r"\W+", lower))
    for topic, keywords in TOPIC_KEYWORDS.items():
        if any(kw in lower or kw in tokens for kw in keywords):
            return topic
    return DEFAULT_TOPIC
