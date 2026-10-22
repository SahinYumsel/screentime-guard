from contextlib import asynccontextmanager
from collections.abc import AsyncGenerator

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.config import settings
from app.db import Base, engine
from app.deps import AppError
from app.routers import devices, rules, usage


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncGenerator[None, None]:
    """Uygulama başlarken veritabanı tablolarını otomatik oluşturur."""
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    description=(
        "Android ekran süresi takip ve uyarı sistemi (screentime-guard) için "
        "kural yönetimi ve kullanım istatistiği mikroservisi."
    ),
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# --- Standart Hata Formatı ({"error": {"code": "...", "message": "..."}}) ---

@app.exception_handler(AppError)
async def app_error_handler(_: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": exc.code,
                "message": exc.message,
            }
        },
    )


@app.exception_handler(RequestValidationError)
async def validation_error_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
    errors = exc.errors()
    first_msg = errors[0].get("msg", "Geçersiz istek verisi.") if errors else "Geçersiz istek verisi."
    field_loc = ".".join(str(loc) for loc in errors[0].get("loc", []) if loc != "body") if errors else ""
    message = f"{field_loc}: {first_msg}" if field_loc else first_msg
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "VALIDATION_ERROR",
                "message": message,
            }
        },
    )


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": f"HTTP_{exc.status_code}",
                "message": str(exc.detail),
            }
        },
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(_: Request, __: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error": {
                "code": "INTERNAL_ERROR",
                "message": "Beklenmeyen bir sunucu hatası oluştu.",
            }
        },
    )


# --- Sağlık Kontrolü (Health Check) ---

@app.get("/v1/health", tags=["health"], summary="Servis sağlık kontrolü")
def health_check() -> dict[str, str]:
    """Mikroservisin ayakta ve çalışır durumda olduğunu doğrular (Token gerektirmez)."""
    return {"status": "ok"}


# --- Router'ları Bağla ---
app.include_router(devices.router)
app.include_router(rules.router)
app.include_router(usage.router)
