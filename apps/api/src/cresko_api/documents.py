import re


def digits_only(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"\D", "", value)


def format_ci(value: str | None) -> str:
    digits = digits_only(value)
    if not digits:
        return ""
    grouped = re.sub(r"\B(?=(\d{3})+(?!\d))", ".", digits)
    return f"V-{grouped}"


def format_rif(value: str | None) -> str:
    digits = digits_only(value)
    if not digits:
        return ""
    if len(digits) <= 1:
        return f"J-{digits}"
    return f"J-{digits[:-1]}-{digits[-1]}"


def format_passport(value: str | None) -> str:
    digits = digits_only(value)
    if not digits:
        return ""
    return f"E-{digits}"


def format_document(document_type: str, value: str | None) -> str | None:
    if not value:
        return value
    if document_type == "ci":
        return format_ci(value)
    if document_type == "rif":
        return format_rif(value)
    if document_type == "passport":
        return format_passport(value)
    return value