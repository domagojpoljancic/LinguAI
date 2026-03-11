"""
App and LLM config from environment.
Single place for OPENAI model and feature flags; ready for real OpenAI testing.
"""

import os

from dotenv import load_dotenv

load_dotenv()

# Debug mode: enables /debug/* endpoints and full request payload logging
DEBUG = os.environ.get("DEBUG", "").lower() in ("true", "1")

# OpenAI: used by workflow nodes. Set OPENAI_API_KEY in .env
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
OPENAI_MODEL = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")

# Placeholder: set to True when you want level-from-words to use LLM instead of heuristic
LEVEL_INFERENCE_USE_LLM = os.environ.get("LEVEL_INFERENCE_USE_LLM", "").lower() in ("true", "1")
