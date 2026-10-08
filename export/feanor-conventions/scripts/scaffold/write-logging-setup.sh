#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: bash scripts/scaffold/write-logging-setup.sh [go|python|typescript]"
    exit 1
}

[[ $# -eq 1 ]] || usage

case "$1" in
  go)
    TARGET="backend/internal/infra/logger.go"
    mkdir -p "$(dirname "$TARGET")"
    cat > "$TARGET" << 'EOF'
import (
    "log/slog"
    "gopkg.in/natefinch/lumberjack.v2"
)

fileWriter := &lumberjack.Logger{
    Filename:  "logs/app.log",
    MaxAge:    8,     // days before deletion
    Compress:  true,  // gzip on rotation
    LocalTime: false, // rotation boundary in UTC
}
logger := slog.New(slog.NewJSONHandler(fileWriter, nil))
EOF
    echo "Written: $TARGET"
    ;;

  python)
    TARGET="backend/app/core/logging.py"
    mkdir -p "$(dirname "$TARGET")"
    cat > "$TARGET" << 'EOF'
import gzip
import logging
import shutil
from datetime import datetime, timedelta, timezone
from logging.handlers import TimedRotatingFileHandler
from pathlib import Path

LOG_DIR = Path("logs")
LOG_DIR.mkdir(exist_ok=True)


class CompressingTimedRotatingFileHandler(TimedRotatingFileHandler):
    """Daily UTC rotation; compresses rotated files older than 3 days; deletes at 8 days."""

    def doRollover(self):
        super().doRollover()
        self._compress_old_logs()

    def _compress_old_logs(self):
        cutoff = datetime.now(timezone.utc) - timedelta(days=3)
        for f in LOG_DIR.glob(f"{Path(self.baseFilename).name}.*"):
            if f.suffix == ".gz":
                continue
            mtime = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc)
            if mtime < cutoff:
                with open(f, "rb") as f_in, gzip.open(f"{f}.gz", "wb") as f_out:
                    shutil.copyfileobj(f_in, f_out)
                f.unlink()


class UTCFormatter(logging.Formatter):
    converter = staticmethod(
        lambda secs, *args: datetime.fromtimestamp(secs, tz=timezone.utc).timetuple()
    )


def get_logger(name: str) -> logging.Logger:
    logger = logging.getLogger(name)
    if not logger.handlers:
        handler = CompressingTimedRotatingFileHandler(
            LOG_DIR / "app.log",
            when="midnight",
            utc=True,
            backupCount=8,
        )
        handler.setFormatter(UTCFormatter(
            "%(asctime)s UTC | %(levelname)-8s | %(name)s:%(funcName)s | %(message)s"
        ))
        stdout_handler = logging.StreamHandler()
        stdout_handler.setFormatter(handler.formatter)
        logger.addHandler(handler)
        logger.addHandler(stdout_handler)
    return logger
EOF
    echo "Written: $TARGET"
    ;;

  typescript)
    TARGET="frontend/src/lib/logger.ts"
    mkdir -p "$(dirname "$TARGET")"
    cat > "$TARGET" << 'EOF'
import pino from "pino";

const logger = pino({
  level: process.env.LOG_LEVEL ?? "info",
  timestamp: pino.stdTimeFunctions.isoTime, // UTC ISO timestamps
  formatters: {
    level: (label) => ({ level: label }),
  },
});

export default logger;

// Usage — structured fields, never interpolation
// logger.info({ orderId, userId }, "order placed");
// logger.error({ err, requestId }, "payment failed");
EOF
    echo "Written: $TARGET"
    ;;

  *)
    echo "Unknown argument: $1"
    usage
    ;;
esac
