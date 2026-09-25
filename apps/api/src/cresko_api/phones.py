import re


def digits(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"\D", "", value)


def format_phone(value: str | None) -> str | None:
    """Normaliza un teléfono venezolano al formato +58 + dígitos.

    - Si el usuario escribió un 0 al inicio, se reemplaza por el código
      de país (58).
    - Si ya trae el código de país (58 o +58), se conserva.
    - Cualquier otro caso se le antepone el código de país.
    """
    if value is None or value.strip() == "":
        return value
    d = digits(value)
    if not d:
        return None
    if d.startswith("0"):
        d = "58" + d[1:]
    elif not d.startswith("58"):
        d = "58" + d
    return f"+{d}"