from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "JojoMusic Core API"
    database_url: str = "sqlite:///./jojomusic.db"
    jwt_secret: str = "change-me"
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 60 * 24 * 7
    resolver_api_url: str = "http://localhost:8001"
    resolver_timeout_seconds: int = 25
    musicbrainz_user_agent: str = "JojoMusic/0.1 (jojomusic@example.com)"
    lastfm_api_key: str = ""
    lastfm_shared_secret: str = ""
    lrclib_base_url: str = "https://lrclib.net"
    spotify_client_id: str = ""
    spotify_client_secret: str = ""
    spotify_redirect_uri: str = "http://127.0.0.1:8000/api/v1/integrations/spotify/callback"
    spotify_scopes: str = (
        "user-library-read user-read-email user-read-private user-read-recently-played"
    )
    genius_access_token: str = ""
    cors_allow_origins: str = (
        "https://jojomusic-web.vercel.app,"
        "http://localhost:3000,"
        "http://127.0.0.1:3000,"
        "http://localhost:8877,"
        "http://127.0.0.1:8877"
    )

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.cors_allow_origins.split(",") if origin.strip()]


settings = Settings()
