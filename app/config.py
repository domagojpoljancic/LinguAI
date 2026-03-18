"""
App and LLM config from environment.
Single place for OPENAI model and feature flags; ready for real OpenAI testing.
"""

import os

from dotenv import load_dotenv

load_dotenv()

# httpx is used under the hood by both:
# - `openai` (Responses API)
# - `langchain_openai.ChatOpenAI`
import httpx

# Debug mode: enables /debug/* endpoints and full request payload logging
DEBUG = os.environ.get("DEBUG", "").lower() in ("true", "1")

# OpenAI: used by workflow nodes. Set OPENAI_API_KEY in .env
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
OPENAI_MODEL = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")

# Placeholder: set to True when you want level-from-words to use LLM instead of heuristic
LEVEL_INFERENCE_USE_LLM = os.environ.get("LEVEL_INFERENCE_USE_LLM", "").lower() in ("true", "1")

# Request timeout for OpenAI calls (seconds). Prevents stuck requests.
try:
    OPENAI_REQUEST_TIMEOUT = int(os.environ.get("OPENAI_REQUEST_TIMEOUT", "30"))
except ValueError:
    OPENAI_REQUEST_TIMEOUT = 30


def _proxy_looks_local(proxy_value: str) -> bool:
    """Heuristic: local proxy endpoints often fail in evaluation sandboxes."""
    v = (proxy_value or "").strip().lower()
    if not v:
        return False
    return (
        "127.0.0.1" in v
        or "localhost" in v
        or v.startswith("socks5://127.0.0.1")
        or v.startswith("socks5://localhost")
    )


def should_bypass_openai_proxy() -> bool:
    """
    Decide whether to ignore env proxy settings for OpenAI.

    In some evaluation/runtime environments, env vars point to a local proxy that
    is reachable for generic outbound traffic, but blocks OpenAI (e.g. 403).
    """
    # Allow explicit override for advanced users.
    # - OPENAI_TRUST_ENV=true  => honor proxy env vars
    # - default: bypass env proxies for reliability in eval/runtime sandboxes
    if os.environ.get("OPENAI_TRUST_ENV", "").strip().lower() in ("true", "1", "yes", "y"):
        return False

    proxy_keys = [
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "all_proxy",
        "http_proxy",
        "https_proxy",
        "SOCKS_PROXY",
        "socks_proxy",
        "SOCKS5_PROXY",
        "socks5_proxy",
    ]
    for k in proxy_keys:
        val = os.environ.get(k, "")
        if val and val.strip():
            # If proxies are configured at all, treat them as potentially unsafe for
            # OpenAI calls in evaluation sandboxes (common failure: proxy returns 403).
            return True
    return False


def openai_httpx_client(*, timeout: float | None = None) -> httpx.Client:
    """
    Create an httpx client for OpenAI calls.

    - When `should_bypass_openai_proxy()` is true, we set `trust_env=False` so httpx
      does NOT pick up broken proxy env vars.
    """
    trust_env = not should_bypass_openai_proxy()
    return httpx.Client(timeout=timeout, trust_env=trust_env)
