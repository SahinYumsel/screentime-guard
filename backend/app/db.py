from collections.abc import Generator
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings

# SQLite için check_same_thread=False gereklidir (FastAPI farklı thread'lerde bağlantı kullanabilir)
connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}

engine = create_engine(
    settings.database_url,
    connect_args=connect_args,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    """Tüm SQLAlchemy modelleri için temel sınıf."""
    pass


def get_db() -> Generator[Session, None, None]:
    """Her HTTP isteği için veritabanı oturumu (session) açıp işlem sonunda kapatan bağımlılık."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
