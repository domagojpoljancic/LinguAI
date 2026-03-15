"""
Centralized logging configuration for LinguAI LangGraph.

Usage:
    from app.logging_config import setup_logging
    setup_logging()
"""

import logging
import os
from typing import Optional

# Two formats:
# - DEV: compact, easy to scan in PyCharm/terminal
# - DEBUG: verbose with module and line info
LOG_FORMAT_DEV = "%(asctime)s | %(levelname)-8s | %(message)s"
LOG_FORMAT_DEBUG = "%(asctime)s | %(levelname)-8s | %(name)s | %(filename)s:%(lineno)d | %(message)s"
DATE_FORMAT = "%Y-%m-%d %H:%M:%S"


def _get_log_level_from_env(default: str = "INFO") -> int:
    """Return log level from LOG_LEVEL env var (defaults to INFO)."""
    level_name = os.environ.get("LOG_LEVEL", default).upper()
    return getattr(logging, level_name, logging.INFO)


def _use_debug_format_from_env() -> bool:
    """Return True when verbose DEBUG formatting is requested."""
    return os.environ.get("LOG_VERBOSE", "").lower() in ("true", "1", "yes", "y")


def setup_logging(level: Optional[int] = None) -> None:
    """
    Configure root logger once with a StreamHandler and standard formatter.

    Safe to call multiple times; subsequent calls are no-ops.
    """
    root = logging.getLogger()

    # Avoid duplicate configuration.
    if getattr(root, "_linguai_logging_configured", False):
        return

    if level is None:
        level = _get_log_level_from_env()

    root.setLevel(level)

    # If there are existing handlers, clear them to avoid duplicate output.
    if root.handlers:
        root.handlers.clear()

    handler = logging.StreamHandler()
    fmt = LOG_FORMAT_DEBUG if _use_debug_format_from_env() else LOG_FORMAT_DEV
    formatter = logging.Formatter(fmt=fmt, datefmt=DATE_FORMAT)
    handler.setFormatter(formatter)
    root.addHandler(handler)

    # Turn down noise from common third-party loggers.
    for noisy in ("httpx", "httpcore", "uvicorn.access"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    # Mark as configured to avoid reconfiguration.
    setattr(root, "_linguai_logging_configured", True)

