# LinguAI Backend (minimal variant)

This subdirectory contains a smaller FastAPI + LangGraph backend implementation for the LinguAI iOS app.

It exposes:
- `GET /` (health)
- `POST /generate-boxes` (vocabulary-box generation)

There is no `/chat` endpoint in this variant (the root of the repo contains the more complete “agentic backend”).

## Run the server
1. Create a virtual environment:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   ```
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Configure environment:
   - Copy the repo-level `.env.example` to `.env`, or set at least `OPENAI_API_KEY` and `DEBUG`.
4. Run:
   ```bash
   uvicorn main:app --reload --host 0.0.0.0 --port 2024
   ```

## Endpoints
### Health
- `GET /` → `{"status":"ok", ...}`

### Generate boxes
`POST /generate-boxes`

Example request:
```bash
curl -s -X POST http://localhost:2024/generate-boxes \
  -H "Content-Type: application/json" \
  -d '{
    "requestId": "req-001",
    "customerId": "cust-1",
    "prompt": "A1 restaurant words in German",
    "defaultLanguage": "en",
    "targetLanguage": "de",
    "existingBoxes": []
  }'
```

## Logs and debug
By default, logs go to stderr (Python `logging`).

When `DEBUG=true`, debug endpoints are enabled:
- `GET /debug/graph/ascii`
- `GET /debug/graph/render`

## Retry safety note
The iOS app’s “AI Suggest” flow is designed to use `(customerId, requestId)` idempotency. This minimal variant may not implement the same persistence-backed replay protection as the repo-root backend—if you need strong mobile retry safety, run the backend from the repo root (`main.py`).

