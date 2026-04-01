from app.domain.tenant import normalize_model_list
from app.security.jwt_tools import hash_password, verify_password


def test_hash_password_roundtrip():
    encoded = hash_password('senha-super-segura')
    assert encoded.startswith('pbkdf2_sha256$')
    assert verify_password('senha-super-segura', encoded) is True
    assert verify_password('senha-errada', encoded) is False


def test_normalize_model_list_removes_duplicates_and_prefixes():
    models = normalize_model_list([
        'models/gemini-2.0-flash',
        ' gemini-2.0-flash ',
        'gemini-1.5-pro-latest',
        '',
    ])
    assert models == ['gemini-2.0-flash', 'gemini-1.5-pro-latest']

