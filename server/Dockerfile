FROM python:3.13-alpine AS builder

ENV PYTHONUNBUFFERED=1

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /server

COPY pyproject.toml .
COPY uv.lock .

RUN uv sync --locked --no-install-project --no-editable

COPY app/ /server/app/

RUN uv sync --locked --no-editable

FROM python:3.13-alpine

ENV PYTHONUNBUFFERED=1

WORKDIR /server

RUN addgroup -S app && adduser -S app -G app

COPY --from=builder --chown=app:app /server/.venv /server/.venv

COPY --from=builder --chown=app:app /server/app ./app

USER app

CMD ["/server/.venv/bin/python", "app/main.py"]