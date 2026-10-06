"""Findings and severities shared by every rule set."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import IntEnum


class Severity(IntEnum):
    INFO = 0
    LOW = 1
    MEDIUM = 2
    HIGH = 3
    CRITICAL = 4

    @classmethod
    def parse(cls, name: str) -> "Severity":
        try:
            return cls[name.strip().upper()]
        except KeyError:
            raise ValueError(f"unknown severity: {name!r}") from None

    @property
    def arabic(self) -> str:
        return {
            Severity.INFO: "معلومة",
            Severity.LOW: "منخفضة",
            Severity.MEDIUM: "متوسطة",
            Severity.HIGH: "عالية",
            Severity.CRITICAL: "حرجة",
        }[self]


@dataclass(frozen=True)
class Finding:
    rule_id: str
    severity: Severity
    title: str
    location: str
    line: int = 0
    evidence: str = ""
    recommendation: str = ""
    cwe: str = ""

    def to_dict(self) -> dict:
        d = asdict(self)
        d["severity"] = self.severity.name.lower()
        return d


@dataclass
class ScanResult:
    target: str
    kind: str
    findings: list[Finding] = field(default_factory=list)
    files_scanned: int = 0
    errors: list[str] = field(default_factory=list)

    def add(self, finding: Finding) -> None:
        self.findings.append(finding)

    def sorted_findings(self) -> list[Finding]:
        seen = set()
        unique = []
        for f in self.findings:
            key = (f.rule_id, f.location, f.line, f.evidence)
            if key not in seen:
                seen.add(key)
                unique.append(f)
        return sorted(unique, key=lambda f: (-f.severity, f.location, f.line, f.rule_id))

    def counts(self) -> dict[str, int]:
        out = {s.name.lower(): 0 for s in Severity}
        for f in self.sorted_findings():
            out[f.severity.name.lower()] += 1
        return out


def clip(text: str, limit: int = 160) -> str:
    """Single-line, length-capped evidence so reports stay readable."""
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def mask_secret(text: str) -> str:
    """Never echo a full secret into a report: keep only its edges."""
    if len(text) <= 8:
        return "*" * len(text)
    return text[:4] + "*" * (len(text) - 8) + text[-4:]
