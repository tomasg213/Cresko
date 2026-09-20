from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv
from pydantic import AnyHttpUrl
from pydantic_settings import BaseSettings, SettingsConfigDict


def _load_repo_env() -> None:
    current = Path(__file__).resolve().parent
    for ancestor in (current, *current.parents):
        env_local = ancestor / ".env.local"
        if env_local.is_file():
            load_dotenv(env_local, override=False)
            return


_load_repo_env()


class Settings(BaseSettings):
    supabase_url: AnyHttpUrl = "http://127.0.0.1:54321"
    supabase_anon_key: str = "replace-me"
    supabase_jwt_secret: str | None = None
    jwt_audience: str = "authenticated"
    jwt_issuer: str | None = None

    model_config = SettingsConfigDict(env_file=(".env", ".env.local"), extra="ignore")

    @property
    def jwks_url(self) -> str:
        return f"{str(self.supabase_url).rstrip('/')}/auth/v1/.well-known/jwks.json"

    @property
    def rest_url(self) -> str:
        return f"{str(self.supabase_url).rstrip('/')}/rest/v1"


@lru_cache
def get_settings() -> Settings:
    return Settings()