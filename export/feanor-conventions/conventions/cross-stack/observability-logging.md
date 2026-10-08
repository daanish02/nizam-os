---
type: convention
title: Logging
description: Structured logging rules, log levels, redaction deny-list, correlation-id propagation, and per-language setup for Go, Python, and TypeScript — baseline, applies to every project.
applies_to: [go, python, typescript]
tags: [observability, logging]
---

# Logging

**Baseline capability — always applies.** Structured logging costs only doing it right the first time, and nothing is diagnosable without it.

Metrics and tracing are **separate, opt-in** capabilities and are not covered here — see `metrics.md` and `tracing.md`. Do not add either by default; both carry real operational cost (a collector, storage, dashboards, alert routing, someone on call). This file covers only what every project gets.

## Cross-Stack Rules

- Structured logging always — key-value pairs as structured fields, never string interpolation into the message body.
- UTC timestamps always — a server's local timezone is an environment detail. UTC is the one timestamp that means the same thing regardless of where the process runs.
- Meaningful log levels:
  - `DEBUG` — dev-only detail, verbose internals.
  - `INFO` — normal lifecycle events (request handled, job completed).
  - `WARN`/`WARNING` — recoverable or degraded situations (fallback used, retry succeeded).
  - `ERROR` — failures needing attention.
- Never log sensitive data — no tokens, passwords, PII, or full request bodies as structured fields.
- **Redact by an explicit deny-list applied in the logger itself**, not by remembering at each call site. A redaction that depends on every future developer remembering is not a control. Minimum set, matched case-insensitively on field name:

  `password`, `passwd`, `secret`, `token`, `access_token`, `refresh_token`, `id_token`, `api_key`, `apikey`, `authorization`, `cookie`, `set-cookie`, `session`, `csrf`, `private_key`, `client_secret`, `card`, `card_number`, `cvv`, `pan`, `iban`, `ssn`, `national_id`, `dob`, `date_of_birth`, `email`, `phone`, `address`, `ip`, `lat`, `lng`

  Replace with `[REDACTED]` — do not truncate. A truncated token is still a partial secret, and a truncated email is still personal data.
- Never log the config object, the environment, or a full exception context that closes over credentials. See `secrets-management.md`.
- Log stable internal identifiers (`user_id`) rather than personal data (`email`), and resolve them at read time. See `data-protection.md` for classification and log retention windows.
- **Propagate a correlation id across services.** Generate one at the edge if the inbound request has none, put it on every log line, and forward it on every outbound call (`traceparent` per W3C Trace Context, or an `X-Request-Id` header) — a correlation id that stops at the service boundary cannot reconstruct a multi-service failure.
- Single log or propagate — never log the same error at multiple layers (double-logging).
- Logging is mandatory at real state changes, errors, and external calls (DB, HTTP, third-party). Not decorative; not silent failure.

## Go

`log/slog` for all logging. JSON handler in production, human-readable locally.

```go
import "log/slog"

// JSON handler in production
logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

// Structured fields — never string concatenation
logger.Info("order placed", "order_id", orderID, "user_id", userID)
```

`slog`'s default clock is local time — override it for UTC timestamps.

For profiling when a real performance question exists: `pprof`. Metrics and tracing are opt-in capabilities — `metrics.md`, `tracing.md`.

### Boilerplate

File handler with rotation (for deployments without an external log aggregator):

```go
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
```

On managed platforms (containers, k8s, PaaS), stdout is the sink — no file handler needed.

## Python

`logging` stdlib. One shared `get_logger(name)` factory per project — no ad-hoc `print()`, no per-module `logging.basicConfig()`.

Contextual data passed via `extra=` or a bound logger, never concatenated into the message.

### Boilerplate

```python
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
```

## TypeScript

Server Components, Server Actions, and API routes: `pino` for structured logging. Never leave `console.log` as the logging mechanism for anything that ships.

On a managed platform (Vercel or similar), that platform's built-in log capture is the sink — no local file rotation needed.

On self-hosted Node/Bun deployments without external log aggregation, use `pino` with `pino-roll` for daily rotation matching the backend retention policy (compressed after 3 days, deleted at 8 days).

### Boilerplate

```typescript
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
logger.info({ orderId, userId }, "order placed");
logger.error({ err, requestId }, "payment failed");
```

Client-side: real errors (uncaught exceptions, failed mutations) reported to an error-tracking service (e.g. Sentry) for production deployments. Not needed for internal/small tools.

On a managed platform, the platform's log capture is the sink and no local rotation applies. Edge runtimes cannot write to disk at all — a file handler there fails at runtime, so stdout is the only correct target.

Related: `metrics.md` and `tracing.md` (both opt-in), `secrets-management.md` (never log a secret), `data-protection.md` (classification and log retention windows).
