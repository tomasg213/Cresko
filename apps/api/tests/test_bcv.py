import asyncio
from typing import Self

import httpx

from cresko_api import bcv


class _FakeResponse:
    def __init__(self, payload: dict) -> None:
        self._payload = payload

    def raise_for_status(self) -> None:
        return None

    def json(self) -> dict:
        return self._payload


class _FakeClient:
    def __init__(self, payload: dict) -> None:
        self._payload = payload

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(self, *args: object) -> bool:
        return False

    async def get(self, url: str) -> _FakeResponse:
        return _FakeResponse(self._payload)


def _patch(payload: dict, monkeypatch) -> None:
    def factory(*args, **kwargs) -> _FakeClient:
        return _FakeClient(payload)

    monkeypatch.setattr(httpx, "AsyncClient", factory)


def test_promedio_is_used_when_present(monkeypatch) -> None:
    payload = {
        "moneda": "USD",
        "fuente": "oficial",
        "nombre": "Dólar",
        "compra": None,
        "venta": None,
        "promedio": 848.5458,
        "fechaActualizacion": "2026-09-18T00:00:00-04:00",
    }
    _patch(payload, monkeypatch)

    rate = asyncio.run(bcv.fetch_bcv_rate())

    assert rate == 848.5458


def test_compra_venta_average_fallback(monkeypatch) -> None:
    payload = {
        "moneda": "USD",
        "casa": "oficial",
        "nombre": "Oficial",
        "compra": 1485,
        "venta": 1535,
    }
    _patch(payload, monkeypatch)

    rate = asyncio.run(bcv.fetch_bcv_rate())

    assert rate == 1510.0


def test_non_official_source_is_rejected(monkeypatch) -> None:
    _patch({"casa": "paralelo", "compra": 2000, "venta": 2100}, monkeypatch)

    try:
        asyncio.run(bcv.fetch_bcv_rate())
        assert False, "expected BcvUnavailableError"
    except bcv.BcvUnavailableError:
        pass


def test_missing_rate_is_rejected(monkeypatch) -> None:
    _patch({"fuente": "oficial", "compra": None, "venta": None, "promedio": None}, monkeypatch)

    try:
        asyncio.run(bcv.fetch_bcv_rate())
        assert False, "expected BcvUnavailableError"
    except bcv.BcvUnavailableError:
        pass