"""nizam_shared — ServiceBase, AuditLogger, and structured logger for nizam-os services."""

from .base import ServiceBase
from .logger import get_logger
from .audit import AuditLogger

__all__ = ["ServiceBase", "get_logger", "AuditLogger"]
