from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from starlette.responses import JSONResponse

from .auth import router as auth_router
from .vault import router as vault_router
from .config import Settings
from .db import create_database_engine, migrate


class BodyLimit:
    def __init__(self, app, limit):
        self.app, self.limit = app, limit

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            return await self.app(scope, receive, send)
        messages, size = [], 0
        while True:
            message = await receive()
            if message['type'] == 'http.disconnect':
                return
            size += len(message.get('body', b''))
            if size > self.limit:
                return await JSONResponse({'detail': {'code': 'body_too_large'}}, 413)(scope, receive, send)
            messages.append(message)
            if not message.get('more_body', False):
                break

        async def replay():
            return messages.pop(0) if messages else await receive()

        await self.app(scope, replay, send)


def create_app(settings=None):
    settings = settings or Settings()

    @asynccontextmanager
    async def lifespan(app):
        migrate(settings)
        app.state.engine = create_database_engine(settings)
        yield
        app.state.engine.dispose()

    app = FastAPI(title='KeyBox', lifespan=lifespan)
    app.include_router(auth_router)
    app.include_router(vault_router)
    app.state.settings = settings
    app.add_middleware(BodyLimit, limit=settings.max_body_bytes)

    @app.exception_handler(RequestValidationError)
    async def invalid_request(request, error):
        return JSONResponse({'detail': {'code': 'invalid_request'}}, status_code=422)

    @app.get('/healthz')
    def health():
        return {'status': 'ok'}

    return app


app = create_app()


