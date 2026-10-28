def test_app_imports_and_registers_orders_routes():
    import main

    paths = {route.path for route in main.app.routes}
    assert {"/api/v1/orders", "/api/v1/orders/meta", "/api/v1/orders/{order_id}/status",
            "/api/v1/catalog/categories", "/api/v1/catalog/products/{product_id}"} <= paths
