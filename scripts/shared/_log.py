"""Shared JSON logger for nizam-os one-shot Python scripts."""

import json
import logging
import sys
from datetime import datetime
from pathlib import Path


class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        return json.dumps({
            "ts": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
            "level": record.levelname,
            "script": record.name,
            "msg": record.getMessage(),
        })


def setup_logging(name: str) -> logging.Logger:
    """Return a logger that writes JSON to stdout and ~/nizam-os/logs/scripts.log."""
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    fmt = _JsonFormatter()

    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(fmt)
    logger.addHandler(sh)

    log_path = Path.home() / "nizam-os" / "logs" / "scripts.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    fh = logging.FileHandler(str(log_path))
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    return logger
