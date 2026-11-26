from app.domain.template_content_rules import (
    validate_body_text,
    validate_button_label,
    validate_footer_text,
    validate_header_text,
)


def test_header_rejects_emoji_and_two_vars():
    assert validate_header_text("Olá *negrito*") is not None
    assert validate_header_text("Oi {{1}} {{2}}") is not None
    assert validate_header_text("Pedido {{1}}") is None


def test_footer_plain_only():
    assert validate_footer_text("Até logo") is None
    assert validate_footer_text("{{1}}") is not None


def test_body_examples_count():
    err = validate_body_text("Olá {{1}}", examples=["João"])
    assert err is None
    err = validate_body_text("Olá {{1}}", examples=[])
    assert err is not None


def test_button_label():
    assert validate_button_label("OK") is None
    assert validate_button_label("😀") is not None