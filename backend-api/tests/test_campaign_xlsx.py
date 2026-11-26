"""Campaign XLSX import/export."""
from __future__ import annotations

from app.services.campaign_xlsx import build_template_xlsx, parse_destinatarios_xlsx


def test_build_and_parse_destinatarios_roundtrip():
    raw = build_template_xlsx(
        template_name="promo_verao",
        category="MARKETING",
        language="pt_BR",
        body_example="Ola {{1}}, use {{2}}",
        variable_columns=["1", "2"],
    )
    rows, errors = parse_destinatarios_xlsx(raw, variable_columns=["1", "2"])
    assert not errors
    assert len(rows) == 1
    row = rows[0]
    assert row["phone"].startswith("55")
    assert row["consent_ok"] is True
    assert row["body_params"]["1"] == "exemplo_1"


def test_parse_rejects_invalid_phone_and_consent():
    raw = build_template_xlsx(
        template_name="t",
        category="UTILITY",
        language="pt_BR",
        body_example="oi",
        variable_columns=[],
    )
    from io import BytesIO
    from openpyxl import load_workbook

    wb = load_workbook(BytesIO(raw))
    ws = wb["Destinatarios"]
    # overwrite example with bad row
    ws.delete_rows(2)
    ws.append(["11999999999", "nao"])
    buf = BytesIO()
    wb.save(buf)
    bad = buf.getvalue()
    rows, errors = parse_destinatarios_xlsx(bad, variable_columns=[])
    assert rows[0]["errors"]
    assert errors