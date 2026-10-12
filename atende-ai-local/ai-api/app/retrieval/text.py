import re
import unicodedata

# Common pt-BR WhatsApp abbreviations -> canonical words (applied on accent-free lowercase tokens).
ABBREVIATIONS = {
    "qto": "quanto", "qnto": "quanto", "qt": "quanto", "qnt": "quanto",
    "vc": "voce", "vcs": "voces", "voc": "voce",
    "hj": "hoje", "amanha": "amanha", "q": "que", "pq": "porque", "tb": "tambem", "tbm": "tambem",
    "hrs": "horas", "hr": "hora", "h": "horas", "ate": "ate",
    "refri": "refrigerante", "refris": "refrigerantes", "2l": "2 litros", "600ml": "600 ml",
    "g": "grande", "gde": "grande", "grd": "grande", "m": "media", "med": "media", "p": "pequena",
    "td": "tudo", "blz": "beleza", "msm": "mesmo", "mto": "muito", "mt": "muito",
    "n": "nao", "naum": "nao", "eh": "e", "ta": "esta", "tah": "esta", "pfv": "por favor", "pf": "por favor",
    "obg": "obrigado", "entrega": "entrega", "entregam": "entrega", "entregao": "entrega",
    "cartao": "cartao", "debto": "debito", "credto": "credito",
}

_TOKEN_RE = re.compile(r"[a-z0-9]+")


def strip_accents(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn")


def normalize(text: str) -> str:
    text = strip_accents(text.lower())
    tokens = _TOKEN_RE.findall(text)
    return " ".join(ABBREVIATIONS.get(t, t) for t in tokens)


def tokens(text: str) -> list[str]:
    return normalize(text).split()


STOPWORDS = frozenset(
    "a o as os um uma uns umas de da do das dos em na no nas nos para pra pro por com sem e ou que "
    "se me te voce voces eu nos ele ela eles elas meu minha seu sua isso esse essa este esta aqui ai la "
    "tem ter qual quais quanto quanta como onde quando sao ser foi vai vou ja mais menos muito bem "
    "oi ola bom boa dia tarde noite por favor obrigado ok sim nao".split()
)


def content_tokens(text: str) -> list[str]:
    return [t for t in tokens(text) if t not in STOPWORDS]
