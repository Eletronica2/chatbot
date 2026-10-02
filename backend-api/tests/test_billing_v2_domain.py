"""Billing V2 pure-domain tests: lead parsing, plan suggestion, margin guard, texts."""
from decimal import Decimal

import pytest
from fastapi import HTTPException

from app.api.access import assert_capability, assert_superadmin
from app.domain.auth import AuthenticatedUser
from app.domain.billing_v2 import (
    MSG_META_DIRECT,
    MSG_VOLUME_UNCONFIRMED,
    CatalogPlan,
    CostInputs,
    compute_margin,
    compute_marketing_margin,
    evaluate_discount,
    normalize_category,
    normalize_mode,
    parse_marketing_answer,
    parse_operational_answer,
    price_for_margin,
    suggest_plan,
    unit_type_for,
    usage_level,
)
from app.domain.outbound_coalescer import coalesce_text_parts
from app.services.ai_usage_service import estimate_cost, extract_usage
from app.services.proposal_service import _assert_no_forbidden, build_included_items

CATALOG = [
    CatalogPlan("PLAN_INICIAL_2026_10", "inicial", "Inicial", Decimal("197"), 1000, False, "2026-10"),
    CatalogPlan("PLAN_ESSENCIAL_2026_10", "essencial", "Essencial", Decimal("297"), 3000, False, "2026-10"),
    CatalogPlan("PLAN_CRESCIMENTO_2026_10", "crescimento", "Crescimento", Decimal("497"), 6000, False, "2026-10"),
    CatalogPlan("PLAN_PROFISSIONAL_2026_10", "profissional", "Profissional", Decimal("897"), 12000, False, "2026-10"),
    CatalogPlan("PLAN_EMPRESARIAL_2026_10", "empresarial", "Empresarial", None, None, True, "2026-10"),
]
MARKETING_PRICE = Decimal("0.55")
WORST_OPERATIONAL = Decimal("0.035")
COMPLETE_COSTS = CostInputs(
    payment_fee_percent=Decimal("0.0399"),
    payment_fee_fixed=Decimal("0.39"),
    tax_rate=Decimal("0.06"),
    ai_cost_per_operational_message=Decimal("0.002"),
    allocated_platform_cost=Decimal("10"),
)


def _user(role: str) -> AuthenticatedUser:
    return AuthenticatedUser(user_id="u1", tenant_id="t1", email="u@example.com", display_name="U", role=role)


# ----------------------------------------------------------------- categories
def test_operational_and_marketing_unit_types():
    assert unit_type_for("SERVICE").value == "operational"
    assert unit_type_for("utility").value == "operational"
    assert unit_type_for("AUTHENTICATION").value == "operational"
    assert unit_type_for("MARKETING").value == "marketing"
    assert normalize_category("marketing_lite") == "MARKETING"
    assert unit_type_for("marketing_lite").value == "marketing"
    assert normalize_category("authentication_international") == "AUTHENTICATION"


def test_billing_mode_default_is_customer_direct():
    assert normalize_mode(None) == "customer_direct"
    assert normalize_mode("solution_partner_credit_line") == "solution_partner_credit_line"
    assert normalize_mode("garbage") == "customer_direct"


def test_usage_levels():
    assert usage_level(799, 1000) == "ok"
    assert usage_level(800, 1000) == "warning"
    assert usage_level(900, 1000) == "alert"
    assert usage_level(1000, 1000) == "exhausted"


# ----------------------------------------------------------------- lead answers
@pytest.mark.parametrize(
    ("answer", "volume", "unknown"),
    [
        ("Até 1.000", 1000, False),
        ("1.001 a 3.000", 3000, False),
        ("3.001 a 6.000", 6000, False),
        ("6.001 a 12.000", 12000, False),
        ("Mais de 12.000", 12001, False),
        ("Ainda não sei", None, True),
        ("", None, True),
        ("800", 800, False),
    ],
)
def test_parse_operational_answer(answer, volume, unknown):
    parsed = parse_operational_answer(answer)
    assert parsed.volume == volume
    assert parsed.unknown is unknown


@pytest.mark.parametrize(
    ("answer", "volume", "unknown"),
    [
        ("Não", 0, False),
        ("Sim, até 100/mês", 100, False),
        ("Até 500/mês", 500, False),
        ("Até 5.000/mês", 5000, False),
        ("Mais de 5.000/mês", 5001, False),
        ("Ainda não sei", None, True),
    ],
)
def test_parse_marketing_answer(answer, volume, unknown):
    parsed = parse_marketing_answer(answer)
    assert parsed.volume == volume
    assert parsed.unknown is unknown


# ----------------------------------------------------------------- plan suggestion (§131)
@pytest.mark.parametrize(
    ("operational", "expected_code"),
    [
        ("800", "PLAN_INICIAL_2026_10"),
        ("1000", "PLAN_INICIAL_2026_10"),
        ("1001", "PLAN_ESSENCIAL_2026_10"),
        ("2500", "PLAN_ESSENCIAL_2026_10"),
        ("5000", "PLAN_CRESCIMENTO_2026_10"),
        ("10000", "PLAN_PROFISSIONAL_2026_10"),
        ("12000", "PLAN_PROFISSIONAL_2026_10"),
        ("20000", "PLAN_EMPRESARIAL_2026_10"),
        ("Mais de 12.000", "PLAN_EMPRESARIAL_2026_10"),
    ],
)
def test_suggest_plan_by_operational_volume(operational, expected_code):
    suggestion = suggest_plan(CATALOG, parse_operational_answer(operational))
    assert suggestion.plan.code == expected_code


def test_suggest_plan_unknown_volume_warns():
    suggestion = suggest_plan(CATALOG, parse_operational_answer("Ainda não sei"))
    assert suggestion.plan.code == "PLAN_INICIAL_2026_10"
    assert suggestion.warning == MSG_VOLUME_UNCONFIRMED


def test_marketing_volume_never_raises_base_plan():
    small = suggest_plan(CATALOG, parse_operational_answer("800"))
    assert small.plan.code == "PLAN_INICIAL_2026_10"
    marketing = parse_marketing_answer("Até 5.000/mês")
    assert marketing.volume == 5000
    assert suggest_plan(CATALOG, parse_operational_answer("800")).plan.code == small.plan.code


@pytest.mark.parametrize(("volume", "estimate"), [(100, Decimal("55.00")), (500, Decimal("275.00"))])
def test_marketing_estimate(volume, estimate):
    assert (MARKETING_PRICE * volume).quantize(Decimal("0.01")) == estimate


# ----------------------------------------------------------------- margin guard (§132)
def test_contribution_margin_is_not_markup():
    result = compute_margin(
        price=Decimal("130"), billing_mode="customer_direct", operational_units=0,
        worst_operational_rate=None,
        costs=CostInputs(payment_fee_percent=Decimal("0"), tax_rate=Decimal("0"),
                         ai_cost_per_operational_message=Decimal("0"), other_costs=Decimal("100")),
    )
    assert result.margin.quantize(Decimal("0.0001")) == Decimal("0.2308")
    assert result.status == "yellow"
    assert price_for_margin(Decimal("100")) == Decimal("142.86")


def test_ten_reais_plan_is_red_and_blocked_in_solution_partner():
    result = compute_margin(
        price=Decimal("10"), billing_mode="solution_partner_credit_line", operational_units=1000,
        worst_operational_rate=WORST_OPERATIONAL, costs=CostInputs(),
    )
    assert result.status == "red"
    decision = evaluate_discount(margin=result, catalog_price=Decimal("197"), reason="cliente pediu desconto")
    assert decision.allowed is False
    assert decision.code == "loss_blocked"


def test_fifteen_percent_is_yellow_and_requires_reason():
    price = (Decimal("35") / Decimal("0.85")).quantize(Decimal("0.01"))
    result = compute_margin(
        price=price, billing_mode="solution_partner_credit_line", operational_units=1000,
        worst_operational_rate=WORST_OPERATIONAL, costs=CostInputs(),
    )
    assert result.status == "yellow"
    assert abs(result.margin - Decimal("0.15")) < Decimal("0.001")
    blocked = evaluate_discount(margin=result, catalog_price=Decimal("197"), reason=None)
    assert blocked.allowed is False and blocked.requires_reason is True
    allowed = evaluate_discount(margin=result, catalog_price=Decimal("197"), reason="contrato anual estratégico")
    assert allowed.allowed is True and allowed.code == "override_with_reason"


def test_green_only_when_cost_basis_complete():
    partial = compute_margin(
        price=Decimal("197"), billing_mode="solution_partner_credit_line", operational_units=1000,
        worst_operational_rate=WORST_OPERATIONAL, costs=CostInputs(),
    )
    assert partial.status == "partial"
    assert set(partial.unknown_components) == {"ai", "payment", "tax"}
    complete = compute_margin(
        price=Decimal("197"), billing_mode="solution_partner_credit_line", operational_units=1000,
        worst_operational_rate=WORST_OPERATIONAL, costs=COMPLETE_COSTS,
    )
    assert complete.unknown_components == []
    assert complete.status == "green"


def test_solution_partner_meta_unknown_is_never_green():
    result = compute_margin(
        price=Decimal("197"), billing_mode="solution_partner_credit_line", operational_units=1000,
        worst_operational_rate=None, costs=COMPLETE_COSTS,
    )
    assert "meta" in result.unknown_components
    assert result.status == "partial"


def test_customer_direct_excludes_meta_but_shows_customer_estimate():
    result = compute_margin(
        price=Decimal("197"), billing_mode="customer_direct", operational_units=1000,
        worst_operational_rate=WORST_OPERATIONAL, costs=COMPLETE_COSTS,
    )
    assert result.costs["meta"] == Decimal("0")
    assert result.meta_customer_estimate == Decimal("35.000")
    assert result.status == "green"


def test_partial_with_discount_requires_reason():
    result = compute_margin(
        price=Decimal("150"), billing_mode="customer_direct", operational_units=1000,
        worst_operational_rate=WORST_OPERATIONAL, costs=CostInputs(),
    )
    assert result.status == "partial"
    assert evaluate_discount(margin=result, catalog_price=Decimal("197"), reason="").allowed is False
    assert evaluate_discount(margin=result, catalog_price=Decimal("197"), reason="parceria local").allowed is True
    assert evaluate_discount(margin=result, catalog_price=Decimal("150"), reason=None).allowed is True


def test_marketing_margin_by_mode():
    sp = compute_marketing_margin(unit_price=MARKETING_PRICE, meta_marketing_rate=Decimal("0.3217"),
                                  billing_mode="solution_partner_credit_line", costs=CostInputs(), units=100)
    assert sp["sold_by_atende"] is True
    assert sp["price"] == "55.00"
    assert sp["meta_cost"] == "32.17"
    assert sp["status"] == "partial"
    cd = compute_marketing_margin(unit_price=MARKETING_PRICE, meta_marketing_rate=Decimal("0.3217"),
                                  billing_mode="customer_direct", costs=CostInputs(), units=100)
    assert cd["sold_by_atende"] is False
    assert cd["message"] == MSG_META_DIRECT


# ----------------------------------------------------------------- proposal texts
def test_solution_partner_proposal_texts():
    items = build_included_items(allowance=3000, billing_mode="solution_partner_credit_line",
                                 marketing_volume=500, marketing_unit_price=MARKETING_PRICE, topups=[])
    joined = "\n".join(items).lower()
    assert "até 3.000 mensagens operacionais entregues/mês" in joined
    assert "campanhas são pré-pagas e o consumo considera mensagens entregues." in joined
    _assert_no_forbidden(items)


def test_customer_direct_proposal_texts():
    items = build_included_items(allowance=1000, billing_mode="customer_direct",
                                 marketing_volume=100, marketing_unit_price=MARKETING_PRICE, topups=[])
    joined = "\n".join(items).lower()
    assert "tarifas da meta: cobradas diretamente pela meta conforme uso e categoria." in joined
    assert "créditos de campanha" not in joined
    _assert_no_forbidden(items)


@pytest.mark.parametrize("text", ["Mensagens ilimitadas", "Meta inclusa", "Tarifa Meta inclusa no plano"])
def test_forbidden_proposal_phrases(text):
    with pytest.raises(ValueError):
        _assert_no_forbidden([text])


# ----------------------------------------------------------------- outbound coalescer
def test_coalescer_joins_fragments_into_one_message():
    result = coalesce_text_parts(["Olá!", "Tudo bem?", "Como posso ajudar?"])
    assert result.parts_before == 3
    assert result.parts_after == 1
    assert result.messages[0] == "Olá!\n\nTudo bem?\n\nComo posso ajudar?"


def test_coalescer_splits_only_over_limit_without_losing_text():
    long = "a" * 5000
    result = coalesce_text_parts(["oi", long], limit=4096)
    assert "".join(result.messages).replace("\n\n", "") == "oi" + long
    assert all(len(m) <= 4096 for m in result.messages)


# ----------------------------------------------------------------- AI usage
def test_ai_usage_extract_and_unknown_cost():
    usage = extract_usage({"ai_usage": {"provider": "gemini", "model": "gemini-2.5-flash",
                                        "input_tokens": 1200, "output_tokens": 300, "cached_tokens": 200}})
    assert usage["input_tokens"] == 1200 and usage["cached_tokens"] == 200
    assert estimate_cost(None, usage) is None
    cost = estimate_cost({"input_per_million": "0.30", "output_per_million": "2.50",
                          "cached_input_per_million": "0.075"}, usage)
    assert cost == Decimal("0.001065")
    assert extract_usage({}) is None


# ----------------------------------------------------------------- RBAC
@pytest.mark.parametrize("role", ["agent", "member", "atendente"])
def test_agent_cannot_manage_billing(role):
    with pytest.raises(HTTPException) as exc:
        assert_capability(_user(role), "canManageBilling")
    assert exc.value.status_code == 403


def test_tenant_admin_can_manage_billing_but_is_not_superadmin():
    assert_capability(_user("owner"), "canManageBilling")
    with pytest.raises(HTTPException):
        assert_superadmin(_user("owner"))


def test_superadmin_passes_all_billing_checks():
    assert_capability(_user("superadmin"), "canManageBilling")
    assert_superadmin(_user("superadmin"))
