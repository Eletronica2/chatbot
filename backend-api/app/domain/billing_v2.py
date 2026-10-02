"""Billing V2 domain: modes, categories, statuses and pure pricing/margin rules."""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from decimal import ROUND_CEILING, ROUND_HALF_UP, Decimal
from enum import Enum
from typing import Any, Iterable


class BillingMode(str, Enum):
    CUSTOMER_DIRECT = "customer_direct"
    SOLUTION_PARTNER = "solution_partner_credit_line"


class MessageCategory(str, Enum):
    SERVICE = "SERVICE"
    UTILITY = "UTILITY"
    AUTHENTICATION = "AUTHENTICATION"
    MARKETING = "MARKETING"


class UnitType(str, Enum):
    OPERATIONAL = "operational"
    MARKETING = "marketing"


class ReservationStatus(str, Enum):
    RESERVED = "reserved"
    ACCEPTED = "accepted"
    COMMITTED = "committed"
    RELEASED = "released"
    PENDING_RECONCILIATION = "pending_reconciliation"


class Entitlement(str, Enum):
    BUCKET = "bucket"
    LEGACY_UNMETERED = "legacy_unmetered"
    META_DIRECT_TRACKING = "meta_direct_tracking"


class LedgerEntryType(str, Enum):
    GRANT = "GRANT"
    RESERVE = "RESERVE"
    COMMIT = "COMMIT"
    RELEASE = "RELEASE"
    EXPIRE = "EXPIRE"
    REVERSAL = "REVERSAL"
    REFUND = "REFUND"
    ADJUSTMENT = "ADJUSTMENT"


SOURCE_PATHS = frozenset(
    {"ai", "manual", "quick_reply", "template", "automation", "flow", "campaign", "system", "retry"}
)
OPERATIONAL_CATEGORIES = frozenset(
    {MessageCategory.SERVICE.value, MessageCategory.UTILITY.value, MessageCategory.AUTHENTICATION.value}
)
CONSUMING_STATUSES = frozenset({"delivered", "read"})
BILLING_MODES = frozenset(mode.value for mode in BillingMode)

MSG_MARKETING_INSUFFICIENT = "Saldo insuficiente de créditos de campanha."
MSG_OPERATIONAL_EXHAUSTED = (
    "Franquia de mensagens operacionais esgotada. Compre um pacote adicional para continuar enviando."
)
MSG_META_DIRECT = "Tarifas da Meta são cobradas diretamente pela Meta."
MSG_VOLUME_UNCONFIRMED = "Volume deve ser confirmado antes do fechamento."

MONEY = Decimal("0.01")
RATE = Decimal("0.000001")


def normalize_category(value: str | None) -> str:
    raw = (value or "").strip().upper()
    if raw in {"AUTH", "AUTHENTICATION_INTERNATIONAL"}:
        return MessageCategory.AUTHENTICATION.value
    if raw.startswith("MARKETING"):
        return MessageCategory.MARKETING.value
    if raw in {m.value for m in MessageCategory}:
        return raw
    return MessageCategory.SERVICE.value


def unit_type_for(category: str) -> UnitType:
    return UnitType.MARKETING if normalize_category(category) == MessageCategory.MARKETING.value else UnitType.OPERATIONAL


def normalize_mode(value: str | None, default: str = BillingMode.CUSTOMER_DIRECT.value) -> str:
    raw = (value or "").strip().lower()
    return raw if raw in BILLING_MODES else default


def usage_level(used: int, allowance: int) -> str:
    """ok | warning (>=80%) | alert (>=90%) | exhausted (>=100%)."""
    if allowance <= 0:
        return "ok"
    ratio = Decimal(used) / Decimal(allowance)
    if ratio >= 1:
        return "exhausted"
    if ratio >= Decimal("0.9"):
        return "alert"
    if ratio >= Decimal("0.8"):
        return "warning"
    return "ok"


# ---------------------------------------------------------------------------
# Lead answers → volumes
# ---------------------------------------------------------------------------
OPERATIONAL_VOLUME_OPTIONS: tuple[str, ...] = (
    "Até 1.000",
    "1.001 a 3.000",
    "3.001 a 6.000",
    "6.001 a 12.000",
    "Mais de 12.000",
    "Ainda não sei",
)
MARKETING_VOLUME_OPTIONS: tuple[str, ...] = (
    "Não",
    "Sim, até 100/mês",
    "Até 500/mês",
    "Até 1.000/mês",
    "Até 5.000/mês",
    "Mais de 5.000/mês",
    "Ainda não sei",
)


def _fold(text: str) -> str:
    return unicodedata.normalize("NFKD", text or "").encode("ascii", "ignore").decode().lower().strip()


def _numbers(text: str) -> list[int]:
    return [int(n.replace(".", "")) for n in re.findall(r"\d[\d.]*", text or "") if n.replace(".", "").isdigit()]


@dataclass(frozen=True)
class VolumeAnswer:
    volume: int | None
    unknown: bool
    raw: str


def parse_operational_answer(answer: str | None) -> VolumeAnswer:
    raw = (answer or "").strip()
    folded = _fold(raw)
    if not folded or "nao sei" in folded:
        return VolumeAnswer(None, True, raw)
    numbers = _numbers(folded)
    if not numbers:
        return VolumeAnswer(None, True, raw)
    top = max(numbers)
    if "mais de" in folded or folded.startswith("acima"):
        top += 1
    return VolumeAnswer(top, False, raw)


def parse_marketing_answer(answer: str | None) -> VolumeAnswer:
    raw = (answer or "").strip()
    folded = _fold(raw)
    if not folded:
        return VolumeAnswer(0, False, raw)
    if "nao sei" in folded:
        return VolumeAnswer(None, True, raw)
    if folded in {"nao", "n"} or folded.startswith("nao"):
        return VolumeAnswer(0, False, raw)
    numbers = _numbers(folded)
    if not numbers:
        return VolumeAnswer(None, True, raw)
    top = max(numbers)
    if "mais de" in folded:
        top += 1
    return VolumeAnswer(top, False, raw)


# ---------------------------------------------------------------------------
# Plan suggestion (catalog V2). Marketing volume never raises the base plan.
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class CatalogPlan:
    code: str
    plan_key: str
    label: str
    price: Decimal | None
    operational_units: int | None
    is_custom: bool
    catalog_version: str


@dataclass(frozen=True)
class PlanSuggestion:
    plan: CatalogPlan
    warning: str | None
    operational_volume: int | None
    reason: str


def suggest_plan(plans: Iterable[CatalogPlan], operational: VolumeAnswer) -> PlanSuggestion:
    ordered = sorted(
        (p for p in plans),
        key=lambda p: (p.is_custom, p.operational_units or 0),
    )
    if not ordered:
        raise ValueError("catalog has no active plans")
    standard = [p for p in ordered if not p.is_custom and p.operational_units]
    custom = next((p for p in ordered if p.is_custom), None)
    if operational.unknown or operational.volume is None:
        return PlanSuggestion(standard[0], MSG_VOLUME_UNCONFIRMED, None, "volume_unknown")
    for plan in standard:
        if operational.volume <= int(plan.operational_units or 0):
            return PlanSuggestion(plan, None, operational.volume, "fits_allowance")
    if custom is not None:
        return PlanSuggestion(custom, None, operational.volume, "above_largest_plan")
    return PlanSuggestion(standard[-1], MSG_VOLUME_UNCONFIRMED, operational.volume, "above_largest_plan")


def marketing_packs(unit_price: Decimal, sizes: Iterable[int] = (100, 500, 1000, 5000)) -> list[dict[str, Any]]:
    return [
        {"units": int(size), "price": (unit_price * Decimal(size)).quantize(MONEY, ROUND_HALF_UP)}
        for size in sizes
    ]


# ---------------------------------------------------------------------------
# Margin engine (contribution margin, not markup)
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class CostInputs:
    target_margin: Decimal = Decimal("0.30")
    payment_fee_percent: Decimal | None = None
    payment_fee_fixed: Decimal | None = None
    tax_rate: Decimal | None = None
    ai_cost_per_operational_message: Decimal | None = None
    allocated_platform_cost: Decimal | None = None
    other_costs: Decimal = Decimal("0")


@dataclass
class MarginResult:
    price: Decimal
    billing_mode: str
    costs: dict[str, Decimal | None]
    known_cost_total: Decimal
    contribution: Decimal
    margin: Decimal | None
    status: str
    unknown_components: list[str]
    minimum_safe_price: Decimal | None
    target_margin: Decimal
    meta_customer_estimate: Decimal | None = None
    notes: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "price": _money(self.price),
            "billing_mode": self.billing_mode,
            "costs": {k: (_money(v) if v is not None else None) for k, v in self.costs.items()},
            "known_cost_total": _money(self.known_cost_total),
            "contribution": _money(self.contribution),
            "margin": (str(self.margin.quantize(Decimal("0.0001"))) if self.margin is not None else None),
            "margin_percent": (
                str((self.margin * 100).quantize(Decimal("0.01"))) if self.margin is not None else None
            ),
            "status": self.status,
            "status_label": STATUS_LABELS.get(self.status, self.status),
            "unknown_components": list(self.unknown_components),
            "minimum_safe_price": _money(self.minimum_safe_price) if self.minimum_safe_price is not None else None,
            "target_margin": str(self.target_margin),
            "meta_customer_estimate": (
                _money(self.meta_customer_estimate) if self.meta_customer_estimate is not None else None
            ),
            "notes": list(self.notes),
        }


STATUS_LABELS = {
    "red": "Prejuízo",
    "yellow": "Margem abaixo de 30%",
    "green": "Margem saudável",
    "partial": "Estimativa parcial",
}


def _money(value: Decimal | None) -> str | None:
    if value is None:
        return None
    return str(value.quantize(MONEY, ROUND_HALF_UP))


def price_for_margin(cost: Decimal, margin: Decimal = Decimal("0.30")) -> Decimal:
    """Price whose contribution margin equals `margin` (cost / (1 - margin))."""
    if margin >= 1:
        raise ValueError("margin must be < 1")
    return (cost / (Decimal(1) - margin)).quantize(MONEY, ROUND_CEILING)


def compute_margin(
    *,
    price: Decimal,
    billing_mode: str,
    operational_units: int,
    worst_operational_rate: Decimal | None,
    costs: CostInputs,
) -> MarginResult:
    price = Decimal(price)
    mode = normalize_mode(billing_mode)
    unknown: list[str] = []
    notes: list[str] = []
    components: dict[str, Decimal | None] = {}
    meta_customer_estimate: Decimal | None = None

    meta_estimate = (
        (worst_operational_rate * Decimal(operational_units)) if worst_operational_rate is not None else None
    )
    if mode == BillingMode.SOLUTION_PARTNER.value:
        if meta_estimate is None:
            unknown.append("meta")
        components["meta"] = meta_estimate
        notes.append("Custo Meta no pior caso operacional (todas as mensagens na categoria mais cara).")
    else:
        components["meta"] = Decimal("0")
        meta_customer_estimate = meta_estimate
        notes.append("Estimativa de custo Meta pago pelo cliente (não entra no custo da Atende Ai).")

    if costs.ai_cost_per_operational_message is None:
        unknown.append("ai")
        components["ai"] = None
    else:
        components["ai"] = costs.ai_cost_per_operational_message * Decimal(operational_units)

    if costs.payment_fee_percent is None and costs.payment_fee_fixed is None:
        unknown.append("payment")
        components["payment"] = None
    else:
        components["payment"] = price * (costs.payment_fee_percent or Decimal(0)) + (
            costs.payment_fee_fixed or Decimal(0)
        )

    if costs.tax_rate is None:
        unknown.append("tax")
        components["tax"] = None
    else:
        components["tax"] = price * costs.tax_rate

    components["allocated_platform"] = costs.allocated_platform_cost
    components["other"] = costs.other_costs or Decimal(0)

    known_total = sum((v for v in components.values() if v is not None), Decimal(0))
    contribution = price - known_total
    margin = (contribution / price) if price > 0 else None

    target = costs.target_margin
    if price <= 0 or (margin is not None and margin < 0):
        status = "red"
    elif margin is not None and margin < target:
        status = "yellow"
    elif unknown:
        status = "partial"
    else:
        status = "green"

    variable_pct = (costs.payment_fee_percent or Decimal(0)) + (costs.tax_rate or Decimal(0))
    fixed_costs = (
        (components["meta"] or Decimal(0))
        + (components["ai"] or Decimal(0))
        + (costs.payment_fee_fixed or Decimal(0))
        + (costs.allocated_platform_cost or Decimal(0))
        + (costs.other_costs or Decimal(0))
    )
    denominator = Decimal(1) - target - variable_pct
    minimum = (fixed_costs / denominator).quantize(MONEY, ROUND_CEILING) if denominator > 0 else None

    return MarginResult(
        price=price,
        billing_mode=mode,
        costs=components,
        known_cost_total=known_total,
        contribution=contribution,
        margin=margin,
        status=status,
        unknown_components=unknown,
        minimum_safe_price=minimum,
        target_margin=target,
        meta_customer_estimate=meta_customer_estimate,
        notes=notes,
    )


def compute_marketing_margin(
    *,
    unit_price: Decimal,
    meta_marketing_rate: Decimal | None,
    billing_mode: str,
    costs: CostInputs,
    units: int = 1,
) -> dict[str, Any]:
    mode = normalize_mode(billing_mode)
    if mode == BillingMode.CUSTOMER_DIRECT.value:
        estimate = (meta_marketing_rate * units) if meta_marketing_rate is not None else None
        return {
            "billing_mode": mode,
            "sold_by_atende": False,
            "meta_customer_estimate": _money(estimate),
            "message": MSG_META_DIRECT,
        }
    price = unit_price * units
    meta = (meta_marketing_rate * units) if meta_marketing_rate is not None else None
    fees = (
        price * (costs.payment_fee_percent or Decimal(0))
        if costs.payment_fee_percent is not None
        else None
    )
    tax = price * costs.tax_rate if costs.tax_rate is not None else None
    known = sum((v for v in (meta, fees, tax) if v is not None), Decimal(0))
    contribution = price - known
    margin = contribution / price if price > 0 else None
    unknown = [name for name, v in (("meta", meta), ("payment", fees), ("tax", tax)) if v is None]
    if price <= 0 or (margin is not None and margin < 0):
        status = "red"
    elif margin is not None and margin < costs.target_margin:
        status = "yellow"
    elif unknown:
        status = "partial"
    else:
        status = "green"
    return {
        "billing_mode": mode,
        "sold_by_atende": True,
        "units": units,
        "price": _money(price),
        "meta_cost": _money(meta),
        "payment_fees": _money(fees),
        "tax": _money(tax),
        "contribution": _money(contribution),
        "margin_percent": str((margin * 100).quantize(Decimal("0.01"))) if margin is not None else None,
        "status": status,
        "status_label": STATUS_LABELS.get(status, status),
        "unknown_components": unknown,
    }


@dataclass(frozen=True)
class DiscountDecision:
    allowed: bool
    requires_reason: bool
    code: str
    message: str


def evaluate_discount(*, margin: MarginResult, catalog_price: Decimal | None, reason: str | None) -> DiscountDecision:
    reason_ok = bool((reason or "").strip()) and len((reason or "").strip()) >= 5
    discounted = catalog_price is not None and margin.price < catalog_price
    if margin.status == "red":
        return DiscountDecision(False, False, "loss_blocked", "Proposta com prejuízo é bloqueada.")
    if margin.status == "yellow":
        if not reason_ok:
            return DiscountDecision(
                False, True, "reason_required", "Margem abaixo de 30%: informe a justificativa."
            )
        return DiscountDecision(True, True, "override_with_reason", "Margem abaixo de 30% aprovada com justificativa.")
    if margin.status == "partial" and discounted and not reason_ok:
        return DiscountDecision(
            False, True, "reason_required", "Estimativa parcial com desconto: informe a justificativa."
        )
    return DiscountDecision(True, discounted, "ok", "ok")
