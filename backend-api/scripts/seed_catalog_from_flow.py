"""Seed a tenant's orders catalog from the prices already published in its flow (no price is invented or changed).

1) Build (local, needs PyYAML):
    python3 backend-api/scripts/seed_catalog_from_flow.py build \
        flow-engine/app/flows/tenants/pizzaria_bella_massa/atendimento_pizzaria_delivery.yaml > /tmp/bella_catalog.json
2) Apply inside the backend container (idempotent: existing names are skipped, never updated):
    docker compose ... exec -T backend-api python -c "$(cat backend-api/scripts/seed_catalog_from_flow.py)" apply \
        pizzaria_bella_massa < /tmp/bella_catalog.json
Prints names and counts only.
"""
import json
import re
import sys

PIZZA_STATES = {
    "pizzas_tradicionais": "Pizzas Tradicionais",
    "pizzas_especiais": "Pizzas Especiais",
    "pizzas_doces": "Pizzas Doces",
}
SIZES = ("Broto", "Média", "Grande")
DRINK_STATE, DRINK_CATEGORY = "bebidas", "Bebidas"
NAME_FIXES = {"Camaão Especial": "Camarão Especial"}
PIZZA_LINE = re.compile(r"^\s*•\s*\*(?P<name>[^*]+)\*\s*—\s*R\$ (?P<a>[\d.,]+) / R\$ (?P<b>[\d.,]+) / R\$ (?P<c>[\d.,]+)\s*$")
DRINK_LINE = re.compile(r"^\s*•\s*\*(?P<name>[^*]+)\*\s*(?:\((?P<desc>[^)]*)\))?\s*—\s*R\$ (?P<price>[\d.,]+)\s*$")


def cents(value: str) -> int:
    reais, _, frac = value.replace(".", "").partition(",")
    return int(reais) * 100 + int((frac or "0").ljust(2, "0")[:2])


def build(flow_path: str) -> dict:
    import yaml

    states = yaml.safe_load(open(flow_path, encoding="utf-8"))["states"]
    categories, products = [], []
    for order, (state, category) in enumerate([*PIZZA_STATES.items(), (DRINK_STATE, DRINK_CATEGORY)]):
        categories.append({"name": category, "sort_order": order})
        lines = (states[state].get("message") or "").splitlines()
        for index, line in enumerate(lines):
            pizza = PIZZA_LINE.match(line) if state in PIZZA_STATES else None
            if pizza:
                name = pizza["name"].strip()
                products.append({"category": category, "name": NAME_FIXES.get(name, name),
                                 "variants": [{"name": size, "price_cents": cents(pizza[k])}
                                              for size, k in zip(SIZES, "abc")]})
                continue
            drink = DRINK_LINE.match(line) if state == DRINK_STATE else None
            if drink:
                price = cents(drink["price"])
                following = lines[index + 1].strip() if index + 1 < len(lines) else ""
                flavors = [f.strip() for f in following.split(",")] if following and not following.startswith("•") \
                    and "," in following else []
                item = {"category": category, "name": drink["name"].strip(), "description": drink["desc"] or ""}
                if flavors:
                    item["variants"] = [{"name": flavor, "price_cents": price} for flavor in flavors]
                else:
                    item["price_cents"] = price
                products.append(item)
    return {"categories": categories, "products": products}


async def apply(tenant: str, payload: dict) -> None:
    from app.db.mysql import MySQLDatabase
    from app.config.settings import settings
    from app.services.catalog_service import CatalogService

    catalog = CatalogService(MySQLDatabase(settings.DATABASE_URL))
    existing_categories = {c["name"]: c for c in await catalog.list_categories(tenant)}
    for category in payload["categories"]:
        if category["name"] not in existing_categories:
            existing_categories[category["name"]] = await catalog.create_category(
                tenant, name=category["name"], sort_order=category["sort_order"])
            print("category created:", category["name"])
    existing_products = {p["name"] for p in await catalog.list_products(tenant)}
    created = 0
    for order, product in enumerate(payload["products"]):
        if product["name"] in existing_products:
            print("product exists (unchanged):", product["name"])
            continue
        data = {k: v for k, v in product.items() if k != "category"}
        data.update(category_id=existing_categories[product["category"]]["id"], sort_order=order, available=True)
        await catalog.create_product(tenant, data)
        created += 1
        print("product created:", product["name"])
    print(f"done: {created} created, {len(payload['products']) - created} skipped")


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "build":
        json.dump(build(sys.argv[2]), sys.stdout, ensure_ascii=False, indent=1)
    elif mode == "apply":
        import asyncio

        asyncio.run(apply(sys.argv[2], json.load(sys.stdin)))
    else:
        raise SystemExit("usage: seed_catalog_from_flow.py build FLOW.yaml | apply TENANT < catalog.json")
