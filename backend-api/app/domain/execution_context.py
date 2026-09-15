"""Execution context distinguishing production vs dry-run automation tests."""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class ExecutionMode(str, Enum):
    NORMAL = "normal"
    TEST = "test"


@dataclass(frozen=True, slots=True)
class ExecutionContext:
    mode: ExecutionMode = ExecutionMode.NORMAL
    persist: bool = True
    allow_external_side_effects: bool = True
    allow_billing: bool = True

    @classmethod
    def production(cls) -> "ExecutionContext":
        return cls(
            mode=ExecutionMode.NORMAL,
            persist=True,
            allow_external_side_effects=True,
            allow_billing=True,
        )

    @classmethod
    def dry_run(cls) -> "ExecutionContext":
        """Automation 'Testar' — no DB writes, no WhatsApp, no billing."""
        return cls(
            mode=ExecutionMode.TEST,
            persist=False,
            allow_external_side_effects=False,
            allow_billing=False,
        )

    @property
    def is_test(self) -> bool:
        return self.mode == ExecutionMode.TEST
