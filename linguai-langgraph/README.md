# linguai-langgraph

Minimal LangGraph backend for the LinguAI iOS app. Exposes a FastAPI server with a health route and a chat endpoint backed by a single-node LangGraph agent (OpenAI gpt-4o-mini).

## Setup

1. **Create a virtual environment**

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate   # Windows: .venv\Scripts\activate
   ```

2. **Install dependencies**

   ```bash
   pip install -r requirements.txt
   ```

3. **Configure environment**

   Copy `.env` or set `OPENAI_API_KEY`:

   ```bash
   # .env
   OPENAI_API_KEY=your_openai_api_key_here
   ```

## Run the server

From the project root:

```bash
uvicorn main:app --reload --port 2024 --host 0.0.0.0
```

Or:

```bash
python main.py
```

**Why `--host 0.0.0.0`?** So the iOS app can connect. By default the server only listens on `127.0.0.1` (this machine only). Binding to `0.0.0.0` accepts connections from other devices on your network.

- On this machine: [http://localhost:2024/](http://localhost:2024/)
- From iPhone/iPad: use your Mac’s IP, e.g. `http://192.168.1.5:2024` (find it in **System Settings → Network**)
- Chat: `POST /chat`

**If you see “Couldn’t connect to server”:** (1) Confirm the server is running. (2) Use `--host 0.0.0.0`. (3) From a physical device, use the computer’s IP and port (e.g. `http://192.168.1.5:2024`), not `localhost`.

## Example request

```bash
curl -X POST http://localhost:2024/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "How do I say thank you in Spanish?"}'
```

Example response:

```json
{"response": "In Spanish you say \"gracias\" for thank you. ..."}
```

## HOW TO SEE LOGS LIVE

Logs go to **stderr** by default (Python’s logging). Where you see them depends on how you run the app:

- **PyCharm Run tool window**  
  Run `main.py` or the “Run FastAPI” configuration. All log lines appear in the **Run** tool window at the bottom. Scroll to see `request_received`, `relevance_check`, `level_resolution`, `topic_identification`, `box_creation_placeholder`, and `request_complete`.

- **PyCharm Debug tool window**  
  Same as Run: run under Debug and watch the **Debug** tool window (console tab). Breakpoints will pause execution; logs before/after appear there.

- **Terminal (uvicorn manually)**  
  Run: `uvicorn main:app --reload --port 2024 --host 0.0.0.0`. All logs print in that terminal. No separate log file unless you redirect (e.g. `... 2> app.log`).

- **Debug mode and payload logging**  
  Set `DEBUG=true` in your environment (or in `.env`). Then:
  - **With DEBUG=true**: the app logs the **full request body** at debug level for each request (`request_payload requestId=... body={...}`). Use this only locally; do not enable in production (privacy).
  - **With DEBUG=false** (or unset): only summary fields are logged (requestId, prompt length, counts, status, level, topic, etc.). No full prompt text or payload in logs.
