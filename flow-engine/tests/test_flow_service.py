from app.domain.flow import FlowDefinition, FlowExecutionRequest, FlowState
from app.services.flow_service import FlowService


def _dummy_flow(name: str) -> FlowDefinition:
    return FlowDefinition(
        name=name,
        start_state="start",
        states={"start": FlowState(state="start", message="ok")},
    )


class _FakeLoader:
    def __init__(
        self,
        *,
        tenant_flows: dict | None = None,
        global_flows: dict | None = None,
    ):
        self._tenant_flows = tenant_flows or {}
        self._global_flows = global_flows or {}

    def get_flow(self, name: str, tenant_id: str | None = None):
        if tenant_id:
            tenant_flow = self._tenant_flows.get(tenant_id, {}).get(name)
            if tenant_flow:
                return tenant_flow
        return self._global_flows.get(name)

    def list_tenant_flows(self, tenant_id: str):
        return dict(self._tenant_flows.get(tenant_id, {}))


def _service(loader: _FakeLoader, default_flow: str = "") -> FlowService:
    return FlowService(loader=loader, runner=None, default_flow=default_flow)


def _request(tenant_id: str, *, flow_name: str | None = None, session_state: dict | None = None):
    message = {"text": "oi"}
    if flow_name:
        message["metadata"] = {"flow": flow_name}
    return FlowExecutionRequest(
        tenant_id=tenant_id,
        phone_number="5534999999999",
        message=message,
        session_state=session_state or {},
    )


def test_selects_explicit_flow_over_tenant_default():
    pizza = _dummy_flow("atendimento_pizzaria_delivery")
    other = _dummy_flow("outro")
    loader = _FakeLoader(
        tenant_flows={"pizzaria_bella_massa": {"atendimento_pizzaria_delivery": pizza, "outro": other}}
    )
    service = _service(loader)
    selected = service._select_flow(_request("pizzaria_bella_massa", flow_name="outro"))
    assert selected is not None
    assert selected.name == "outro"


def test_selects_session_active_flow():
    pizza = _dummy_flow("atendimento_pizzaria_delivery")
    loader = _FakeLoader(tenant_flows={"pizzaria_bella_massa": {"atendimento_pizzaria_delivery": pizza}})
    service = _service(loader)
    selected = service._select_flow(
        _request(
            "pizzaria_bella_massa",
            session_state={"active_flow": "atendimento_pizzaria_delivery"},
        )
    )
    assert selected is not None
    assert selected.name == "atendimento_pizzaria_delivery"


def test_uses_sole_tenant_flow_when_no_session_flow():
    pizza = _dummy_flow("atendimento_pizzaria_delivery")
    loader = _FakeLoader(tenant_flows={"pizzaria_bella_massa": {"atendimento_pizzaria_delivery": pizza}})
    service = _service(loader, default_flow="")
    selected = service._select_flow(_request("pizzaria_bella_massa"))
    assert selected is not None
    assert selected.name == "atendimento_pizzaria_delivery"


def test_does_not_use_missing_legacy_start_default():
    pizza = _dummy_flow("atendimento_pizzaria_delivery")
    loader = _FakeLoader(
        tenant_flows={"pizzaria_bella_massa": {"atendimento_pizzaria_delivery": pizza, "extra": _dummy_flow("extra")}}
    )
    service = _service(loader, default_flow="start")
    selected = service._select_flow(_request("pizzaria_bella_massa"))
    assert selected is None


def test_tenant_without_flows_is_unhandled():
    loader = _FakeLoader(tenant_flows={}, global_flows={})
    service = _service(loader, default_flow="start")
    selected = service._select_flow(_request("loja_centro_demo"))
    assert selected is None


def test_does_not_leak_another_tenant_flow():
    pizza = _dummy_flow("atendimento_pizzaria_delivery")
    loader = _FakeLoader(tenant_flows={"pizzaria_bella_massa": {"atendimento_pizzaria_delivery": pizza}})
    service = _service(loader)
    selected = service._select_flow(_request("loja_centro_demo"))
    assert selected is None
