"""
Deterministic topic tagging for vocabulary rows.

Maps headwords / default_text to product topic keys: restaurant, travel, business,
dating, shopping, health, daily, general. First matching topic wins (order matters).
"""

import re
from typing import Optional

# Keyword sets per topic (lowercase). Match is WHOLE-TOKEN only to avoid false positives
# (e.g. "bar" must be a full word, not substring of "barber", "bargain"). Add compound forms explicitly.
TOPIC_KEYWORDS: dict[str, list[str]] = {
    "restaurant": [
        "restaurant", "food", "dining", "menu", "kitchen", "cooking", "recipe", "cafe", "bar", "pub",
        "barbecue", "bartender",
        "eat", "meal", "waiter", "waitress", "bill", "table", "fork", "knife", "spoon", "plate", "glass",
        "reservation", "water", "drink", "wine", "beer", "coffee", "tea", "breakfast", "lunch", "dinner",
        "dish", "salad", "soup", "meat", "fish", "vegetable", "fruit", "dessert", "chef", "hungry",
        "snack", "ingredient", "order", "tip", "pizza", "pasta", "sandwich", "bottle",
    ],
    "travel": [
        "travel", "airport", "hotel", "hostel", "vacation", "trip", "flight", "directions", "transport",
        "ticket", "train", "bus", "plane", "passport", "luggage", "suitcase", "boarding", "arrival",
        "departure", "journey", "destination", "tour", "tourist", "abroad", "accommodation",
        "station", "port", "map", "visa", "backpack",
    ],
    "business": [
        "business", "meeting", "office", "work", "email", "presentation", "negotiation", "deadline",
        "invoice", "contract", "agenda", "report", "colleague", "boss", "employ", "salary", "manager",
        "company", "interview", "career", "account", "accountant", "conference", "client",
        "workplace", "worker", "teamwork", "paperwork",
    ],
    "dating": [
        "dating", "romance", "relationship", "love", "flirt", "partner", "date", "marry", "wedding",
        "couple", "kiss", "marriage",
    ],
    "shopping": [
        "shopping", "store", "market", "buy", "sell", "price", "cost", "clothes", "shop", "discount",
        "cashier", "receipt", "cash", "card", "credit", "payment", "purchase", "sale", "customer",
    ],
    "health": [
        "health", "doctor", "pharmacy", "hospital", "medicine", "symptom", "symptoms", "appointment",
        "pain", "ache", "ill", "sick", "nurse", "patient", "disease", "fever", "blood", "medical",
        "ambulance", "prescription", "vitamin", "vaccine",
    ],
    "daily": [
        "daily", "routine", "everyday", "greetings", "hello", "goodbye", "please", "thank", "sorry",
        "yes", "no", "basic", "number", "one", "two", "three", "morning", "evening", "afternoon",
        "day", "week", "month", "year", "time", "today", "tomorrow", "yesterday", "o'clock",
        "weekday", "weekend", "calendar", "clock", "minute", "hour",
    ],
}
# Keywords used only for sense/gloss scoring (Wiktionary gloss text). Not used for headword tagging.
# Helps prefer e.g. restaurant-bill sense ("invoice", "payment") over law sense ("draft", "law").
TOPIC_SENSE_KEYWORDS: dict[str, list[str]] = {
    "restaurant": [
        "invoice", "check", "payment", "services", "sold", "goods", "alcoholic", "drinks", "beverage",
        "meal", "food", "drink", "restaurant", "cafe", "bar", "pub", "waiter", "order", "menu",
    ],
    "travel": [
        "aircraft", "airplane", "flight", "airport", "vehicle", "travel", "journey", "trip",
        "passport", "luggage", "hotel", "transport", "boarding", "destination",
    ],
    "business": [
        "draft", "law", "legislative", "bill", "legal", "meeting", "office", "contract", "invoice",
    ],
    "daily": [
        "time", "o'clock", "hour", "minute", "clock", "watch", "device", "instrument", "measure",
    ],
}
# Fallback: if topic has no sense keywords, use topic keywords for scoring
for _topic, _kws in TOPIC_KEYWORDS.items():
    if _topic not in TOPIC_SENSE_KEYWORDS:
        TOPIC_SENSE_KEYWORDS[_topic] = _kws

DEFAULT_TOPIC = "general"


def tag_topic(default_text: str) -> str:
    """Return a single topic key for default_text (deterministic).
    Matches only whole tokens (and exact phrase) so e.g. 'bar' matches 'bar' but not 'barber'.
    """
    if not default_text:
        return DEFAULT_TOPIC
    lower = default_text.lower().strip()
    tokens = set(re.split(r"\W+", lower))
    for topic, keywords in TOPIC_KEYWORDS.items():
        if any((kw in tokens) or (lower == kw) for kw in keywords):
            return topic
    return DEFAULT_TOPIC
