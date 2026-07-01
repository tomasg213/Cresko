from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    PROJECT_NAME: str = "Cresko"
    VERSION: str = "0.1.0"

    DATABASE_URL: str = "postgresql+asyncpg://cresko:cresko@localhost:5432/cresko"
    DATABASE_URL_SYNC: str = "postgresql://cresko:cresko@localhost:5432/cresko"

    JWT_SECRET: str = "change-this-secret-in-production"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRATION_MINUTES: int = 60

    TENANT_HEADER: str = "X-Tenant-ID"

    model_config = {"env_file": ".env"}


settings = Settings()
