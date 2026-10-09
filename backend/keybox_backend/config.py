from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix='KEYBOX_')
    database_url: str = 'sqlite:///./keybox.db'
    max_body_bytes: int = 2 * 1024 * 1024
    access_seconds: int = 15 * 60
    refresh_seconds: int = 30 * 24 * 60 * 60
    login_limit: int = 5
    login_window_seconds: int = 15 * 60
