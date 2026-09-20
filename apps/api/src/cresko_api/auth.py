from dataclasses import dataclass
from typing import Any

import jwt
from fastapi import HTTPException, status
from jwt import PyJWKClient

from .config import Settings


@dataclass(frozen=True)
class AuthenticatedUser:
    id: str
    claims: dict[str, Any]


def _unauthorized() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or missing authentication token",
        headers={"WWW-Authenticate": "Bearer"},
    )


def decode_access_token(token: str, settings: Settings) -> AuthenticatedUser:
    try:
        options = {"verify_aud": bool(settings.jwt_audience)}
        issuer = settings.jwt_issuer

        if settings.supabase_jwt_secret:
            claims = jwt.decode(
                token,
                settings.supabase_jwt_secret,
                algorithms=["HS256"],
                audience=settings.jwt_audience,
                issuer=issuer,
                options=options,
            )
        else:
            signing_key = PyJWKClient(settings.jwks_url).get_signing_key_from_jwt(token)
            claims = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256", "ES256"],
                audience=settings.jwt_audience,
                issuer=issuer,
                options=options,
            )
    except (jwt.PyJWTError, ValueError, TypeError):
        raise _unauthorized() from None

    user_id = claims.get("sub")
    if not isinstance(user_id, str) or not user_id:
        raise _unauthorized()

    return AuthenticatedUser(id=user_id, claims=claims)
