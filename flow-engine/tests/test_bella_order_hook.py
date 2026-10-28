from pathlib import Path

import yaml

from app.services.flow_loader import FlowLoader
from tests.test_flow_runner import _request, _run

BELLA = Path(__file__).resolve().parents[1] / "app/flows/tenants/pizzaria_bella_massa/atendimento_pizzaria_delivery.yaml"


def _bella():
    return FlowLoader(BELLA.parents[3])._parse_flow(BELLA, yaml.safe_load(BELLA.read_text(encoding="utf-8")))


def test_order_start_state_exposes_start_order_hook():
    flow = _bella()
    for text, state in [("quero", "pizzas_tradicionais"), ("pedido", "horario_funcionamento")]:
        response = _run(flow, _request(text, state=state))
        assert response.metadata["state"] == "iniciar_pedido"
        assert response.metadata["hook"] == {"action": "start_order", "return_state": "boas_vindas"}


def test_knowledge_section_does_not_break_loading():
    data = yaml.safe_load(BELLA.read_text(encoding="utf-8"))
    assert len(data["knowledge"]["documents"]) == 8
    assert "boas_vindas" in _bella().states
