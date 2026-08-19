from datetime import datetime
from zoneinfo import ZoneInfo

from app.services.business_hours import apply_contextual_cta, open_status

TZ = ZoneInfo("America/Sao_Paulo")
HOURS = {
    "timezone": "America/Sao_Paulo",
    "schedule": {
        "friday": {"open": "18:00", "close": "00:00"},
    },
}


def test_closed_friday_morning():
    moment = datetime(2026, 5, 15, 11, 48, tzinfo=TZ)  # Friday
    is_open, hint = open_status(HOURS, now=moment)
    assert is_open is False
    assert "18h" in hint


def test_cta_when_closed():
    moment = datetime(2026, 5, 15, 11, 48, tzinfo=TZ)  # Friday morning, closed
    msg = "Horários:\n\n{cta_pedido}"
    out = apply_contextual_cta(msg, HOURS, now=moment)
    assert "fechados" in out.lower()
    assert "pedido" not in out.lower() or "cardápio" in out.lower()
