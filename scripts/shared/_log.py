"""Shared logger for nizam-os one-shot Python scripts."""

import json
import logging
import sys
from datetime import datetime
from pathlib import Path

_COLORS = {
    "INFO": "\033[0;32m",
    "WARNING": "\033[0;33m",
    "ERROR": "\033[0;31m",
}
_RESET = "\033[0m"


class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        return json.dumps({
            "ts": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
            "level": record.levelname,
            "script": record.name,
            "msg": record.getMessage(),
        }, separators=(',', ':'))


class _ColorFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        ts = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        color = _COLORS.get(record.levelname, "")
        tag = record.levelname[:4]
        return f"{color}[{tag}]{_RESET}  {ts} {record.getMessage()}"


def setup_logging(name: str) -> logging.Logger:
    """Return a logger that writes colored output to stdout (TTY) or JSON (piped), and JSON to file."""
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)

    sh = logging.StreamHandler(sys.stdout)
    if sys.stdout.isatty():
        sh.setFormatter(_ColorFormatter())
    else:
        # JSON when piped — structured for journald ingestion
        sh.setFormatter(_JsonFormatter())
    logger.addHandler(sh)

    log_path = Path.home() / "nizam-os" / "logs" / "scripts.log"  # overridable: set NIZAM_LOG=/path/to/file.log
    log_path.parent.mkdir(parents=True, exist_ok=True)
    fh = logging.FileHandler(str(log_path))
    fh.setFormatter(_JsonFormatter())
    logger.addHandler(fh)

    return logger
