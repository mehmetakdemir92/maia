FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
ENV PORT=8080
# python:3.11-slim ships no locale, so Python can fall back to ASCII for
# stdlib text operations. Kept as container hygiene — note it does NOT
# affect outgoing HTTP headers, which httpx always encodes as ASCII by
# spec regardless of locale.
ENV PYTHONUTF8=1
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
