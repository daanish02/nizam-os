"""Append-only audit log writer. Uses an independent DB connection per write so records commit even if the caller's transaction rolls back."""

import json

import psycopg


class AuditLogger:
    """Write immutable audit records to audit.log.

    Opens its own connection per write so the record commits even if the
    caller's transaction rolls back.
    """

    def __init__(self, dsn: str) -> None:
        self._dsn = dsn

    def log(
        self,
        *,
        actor: str,
        schema_name: str,
        table_name: str,
        operation: str,
        row_id: int | None = None,
        before_state: dict | None = None,
        after_state: dict | None = None,
    ) -> None:
        """Insert one audit record: actor, schema/table/operation, row_id, before/after JSON."""
        with psycopg.connect(self._dsn, autocommit=True) as conn:
            conn.execute(
                """
                INSERT INTO audit.log
                    (schema_name, table_name, operation, actor, row_id, before_state, after_state)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    schema_name,
                    table_name,
                    operation,
                    actor,
                    row_id,
                    json.dumps(before_state) if before_state is not None else None,
                    json.dumps(after_state) if after_state is not None else None,
                ),
            )
