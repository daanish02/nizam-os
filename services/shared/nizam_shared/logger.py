import json
import logging
import sys
from datetime import datetime, timezone


class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry: dict = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "service": record.name,
            "msg": record.getMessage(),
        }
        if record.exc_info:
            entry["exc"] = self.formatException(record.exc_info)
        for key in ("module", "func"):
            val = record.__dict__.get(key)
            if val is not None:
                entry[key] = val
        for key, val in record.__dict__.items():
            if key not in logging.LogRecord.__dict__ and not key.startswith("_") and key not in entry:
                entry[key] = val
        return json.dumps(entry, default=str)


def get_logger(name: str) -> logging.Logger:
    """Return a JSON-to-stderr logger. Pass extra={"module": ..., "func": ...} for context."""
    logger = logging.getLogger(name)
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stderr)
        handler.setFormatter(_JsonFormatter())
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
        logger.propagate = False
    return logger
