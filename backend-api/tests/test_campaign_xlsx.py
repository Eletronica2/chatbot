"""Campaign XLSX import/export."""
from __future__ import annotations

from io import BytesIO

from openpyxl import load_workbook

from app.services.campaign_metrics import presentation_counts
from app.services.campaign_xlsx import build_results_xlsx, build_template_xlsx, parse_destinatarios_xlsx


def test_presentation_rates():
    zero = presentation_counts(sent=0, delivered=0, failed=0)
    assert zero["delivery_rate"] is None
    without_evidence = presentation_counts(delivered=1, failed=1)
    assert without_evidence["sent"] == 1
    assert without_evidence["delivery_rate"] == 100
    with_evidence = presentation_counts(delivered=1, failed=1, failed_accepted=1)
    assert with_evidence["sent"] == 2
    assert with_evidence["delivery_rate"] == 50
    full = presentation_counts(delivered=1)
    assert full["sent"] == 1
    assert full["delivered"] == 1
    assert full["delivery_rate"] == 100


def test_template_has_no_fake_rows_and_parses_friendly_headers():
    raw = build_template_xlsx(
        template_name="promo",
        category="UTILITY",
        language="pt_BR",
        body_example="Oi {{1}}",
        variable_columns=["1"],
    )
    wb = load_workbook(BytesIO(raw))
    assert wb.sheetnames[0] == "Destinatarios"
    assert wb["Destinatarios"].max_row == 1
    assert "Consentimento" not in [c.value for c in wb["Destinatarios"][1]]
    ws = wb["Destinatarios"]
    ws.append(["5534999999999", "Arthur"])
    buf = BytesIO()
    wb.save(buf)
    rows, errors = parse_destinatarios_xlsx(buf.getvalue(), variable_columns=["1"])
    assert not errors
    assert rows[0]["body_params"]["1"] == "Arthur"
    assert rows[0]["phone"] == "5534999999999"


def test_explicit_denial_is_not_covered_by_missing_column_rules():
    raw = build_template_xlsx(
        template_name="promo",
        category="UTILITY",
        language="pt_BR",
        body_example="Oi {{1}}",
        variable_columns=["1"],
    )
    wb = load_workbook(BytesIO(raw))
    ws = wb["Destinatarios"]
    ws.cell(1, 3, "consentimento")
    ws.append(["5534999999999", "Ana", "sim"])
    ws.append(["5534888888888", "Bia", "não"])
    buf = BytesIO()
    wb.save(buf)
    rows, errors = parse_destinatarios_xlsx(buf.getvalue(), variable_columns=["1"])
    assert rows[0]["consent_ok"] is True and not rows[0]["errors"]
    assert rows[1]["consent_denied"] is True
    assert errors


def test_results_hide_wamid_and_keep_estimate():
    raw = build_results_xlsx(
        campaign_name="Homolog",
        template_name="promo",
        category="UTILITY",
        status="completed",
        recipients=[
            {
                "phone_e164": "5534992665547",
                "status": "delivered",
                "provider_message_id": "wamid.SECRET",
                "body_params": {"1": "Arthur", "2": "TESTE002"},
            }
        ],
        consumption_estimate={"consumption_estimate": "0.035", "currency": "BRL"},
        status_totals=presentation_counts(delivered=1),
    )
    wb = load_workbook(BytesIO(raw))
    assert wb.sheetnames[0] == "Resumo"
    blob = " ".join(str(c.value) for row in wb["Destinatarios"].iter_rows() for c in row)
    assert "wamid" not in blob.lower()
    assert "Arthur" in blob
