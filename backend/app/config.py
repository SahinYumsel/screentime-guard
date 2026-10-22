from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Uygulama yapılandırma ayarları (ortam değişkenleri veya varsayılanlar)."""

    app_name: str = "screentime-guard API"
    app_version: str = "1.0.0"
    database_url: str = "sqlite:///./screentime_guard.db"

    # Yeni kayıt olan cihazlar için varsayılan kural değerleri
    default_daily_limit_min: int = 120
    default_cutoff_start: str = "23:00"
    default_cutoff_end: str = "06:00"
    default_rule_mode: str = "notify"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
