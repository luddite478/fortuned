FROM python:3.13-alpine AS builder

ENV PYTHONUNBUFFERED=1

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

# Copy dependency files
COPY pyproject.toml .
COPY uv.lock .

# Install dependencies
RUN uv sync --locked --no-install-project --no-editable

# Copy source code
COPY main.py /app/
COPY src/ /app/src/

# Install the project
RUN uv sync --locked --no-editable

FROM python:3.13-alpine

WORKDIR /app

RUN addgroup -S app && adduser -S app -G app

COPY --from=builder --chown=app:app /app/.venv /app/.venv

COPY --from=builder --chown=app:app /app/main.py .
COPY --from=builder --chown=app:app /app/src ./src

USER app

EXPOSE 8765

CMD ["/app/.venv/bin/python", "main.py"]