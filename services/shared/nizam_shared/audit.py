import json
import psycopg


class AuditLogger:
    """Write immutable audit records to knowledge.vault_audit."""

    def __init__(self, dsn: str) -> None:
        self._dsn = dsn

    def log(
        self,
        *,
        profile: str,
        action: str,
        approved: bool,
        file_path: str | None = None,
        title: str | None = None,
        details: dict | None = None,
    ) -> None:
        """Insert one audit record. Opens and closes its own connection so the
        record commits even if the caller's transaction rolls back."""
        with psycopg.connect(self._dsn, autocommit=True) as conn:
            conn.execute(
                """
                INSERT INTO knowledge.vault_audit
                    (profile, action, file_path, title, approved, details)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (
                    profile,
                    action,
                    file_path,
                    title,
                    approved,
                    json.dumps(details) if details is not None else None,
                ),
            )
