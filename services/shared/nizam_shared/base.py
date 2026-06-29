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
    - AuditLogger writing to knowledge.vault_audit
    - Redis client for short-lived caching
    """

    def __init__(self, name: str) -> None:
        self.name = name
        self.logger = get_logger(name)

        pg_pass = os.environ["POSTGRES_SVC_KNOWLEDGE_PASS"]
        pg_host = os.environ.get("POSTGRES_HOST", "localhost")
        pg_port = os.environ.get("POSTGRES_PORT", "5432")
        pg_db = os.environ.get("POSTGRES_DB", "nizam")
        self.dsn = f"postgresql://svc_knowledge:{pg_pass}@{pg_host}:{pg_port}/{pg_db}"

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
