import httpx

DOLARAPI_URL = "https://ve.dolarapi.com/v1/dolares/oficial"


class BcvUnavailableError(Exception):
    pass


def _to_float(value) -> float | None:
    if value is None:
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result


async def fetch_bcv_rate() -> float:
    """Fetch the official BCV rate from dolarapi.com.

    The API may expose the rate as ``promedio`` or as ``compra``/``venta``.
    Prefers ``promedio`` when present; otherwise uses the average of the
    official compra/venta. Raises BcvUnavailableError when the rate cannot be
    parsed, so the caller can fall back to the stored/manual rate.
    """
    try:
        async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as client:
            response = await client.get(DOLARAPI_URL)
            response.raise_for_status()
            payload = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        raise BcvUnavailableError("No se pudo conectar con dolarapi.com") from exc

    if not isinstance(payload, dict):
        raise BcvUnavailableError("dolarapi.com no devolvió un objeto JSON")

    source = payload.get("casa") or payload.get("fuente")
    if source is not None and source != "oficial":
        raise BcvUnavailableError("dolarapi.com no devolvió el dólar oficial")

    promedio = _to_float(payload.get("promedio"))
    if promedio is not None and promedio > 0:
        return round(promedio, 4)

    compra = _to_float(payload.get("compra"))
    venta = _to_float(payload.get("venta"))
    if compra is not None and venta is not None and compra > 0 and venta > 0:
        return round((compra + venta) / 2, 2)

    raise BcvUnavailableError("Tasa oficial no encontrada en la respuesta de dolarapi.com")