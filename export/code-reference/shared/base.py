"""ServiceBase — shared DB, Redis, and audit wiring for nizam-os MCP services. Requires POSTGRES_DSN env var."""

import os
from contextlib import contextmanager
from typing import Generator

import psycopg
import redis
from psycopg.rows import dict_row

from .audit import AuditLogger
from .logger import get_logger


class ServiceBase:
    """Common wiring for all nizam-os MCP services.

    Provides:
    - JSON structured logger (stderr)
    - psycopg3 connection factory (dict rows, auto commit/rollback)
    - AuditLogger writing to audit.log
    - Redis client for short-lived caching
    """

    def __init__(self, name: str) -> None:
        self.name = name
        self.logger = get_logger(name)

        self.dsn = os.environ["POSTGRES_DSN"]
        self.audit = AuditLogger(self.dsn)

        redis_url = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
        self.cache: redis.Redis = redis.from_url(redis_url, decode_responses=True)

    @contextmanager
    def db(self) -> Generator[psycopg.Connection, None, None]:
        """Yield a psycopg3 connection with dict row factory.

        Commits on clean exit, rolls back on exception.
        """
        with psycopg.connect(self.dsn, row_factory=dict_row) as conn:
            yield conn
