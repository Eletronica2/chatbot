from app.services.campaign_status import should_promote


def test_should_promote_delivered_after_sent():
    assert should_promote("sent", "delivered")
    assert not should_promote("delivered", "sent")
    assert should_promote("sent", "read")
    assert should_promote("sent", "failed")
    assert not should_promote("read", "failed")