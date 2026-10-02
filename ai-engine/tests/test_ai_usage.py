from app.services.ai_service import AIService


def test_gemini_usage_metadata_is_extracted():
    usage = AIService._extract_usage(
        {"usageMetadata": {"promptTokenCount": 1200, "candidatesTokenCount": 300, "cachedContentTokenCount": 200}},
        "gemini",
        "gemini-2.5-flash",
    )
    assert usage == {
        "provider": "gemini",
        "model": "gemini-2.5-flash",
        "input_tokens": 1200,
        "output_tokens": 300,
        "cached_tokens": 200,
    }


def test_missing_usage_stays_unknown_not_zero():
    usage = AIService._extract_usage({}, "gemini", None)
    assert usage["input_tokens"] is None
    assert usage["output_tokens"] is None


def test_openai_usage_is_extracted():
    usage = AIService._extract_usage(
        {"model": "gpt-4o-mini", "usage": {"prompt_tokens": 50, "completion_tokens": 20,
                                           "prompt_tokens_details": {"cached_tokens": 10}}},
        "openai",
        None,
    )
    assert (usage["input_tokens"], usage["output_tokens"], usage["cached_tokens"]) == (50, 20, 10)
