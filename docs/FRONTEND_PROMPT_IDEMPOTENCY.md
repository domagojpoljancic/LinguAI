# Frontend prompt: adopt backend idempotency and duplicate protection

Use this as a prompt or spec when updating the LinguAI iOS app to work with the latest backend changes.

---

## Backend changes (summary)

The **POST /generate-boxes** backend now has **real idempotency** and **duplicate protection**:

1. **Idempotency key:** `(customerId, requestId)` — both must be sent on every request and must be stable for the same logical “generate boxes” action.
2. **Exact replay:** If the same `customerId` and `requestId` are sent again with the **same payload** (prompt, defaultLanguage, targetLanguage, existingBoxes), the backend returns the **cached response** (same JSON as the first time) and does **not** run the workflow again. No duplicate boxes, no duplicate work.
3. **Conflict:** If the same `(customerId, requestId)` is sent again with a **different payload** (e.g. user changed the prompt and you reused the same requestId), the backend returns **HTTP 409 Conflict** with a JSON body like:  
   `{"detail": "Idempotency conflict: this requestId was already used with a different payload for this customer."}`
4. **Success-only caching:** Only successful generations (`status == "generated_placeholder"`) are cached. Failed or low-confidence responses are not cached, so retrying after a failure is safe and will run the workflow again.

Request and response **body shapes are unchanged**. The only new behavior is: **409** for the conflict case above.

---

## What the frontend must do

1. **Send a stable `requestId` per “generate” action**  
   - Generate a unique ID when the user initiates “generate box” (e.g. UUID).  
   - Use that **same** `requestId` for **retries** of that exact action (same prompt, same languages, same existingBoxes).  
   - Use a **new** `requestId` for a **new** user action (e.g. user tapped “Generate” again with a different prompt or after changing options).

2. **Send a stable `customerId`**  
   - Identify the current user/device consistently (e.g. persistent device ID or account ID).  
   - Same value for all requests from that user so the backend can scope idempotency per customer.

3. **Handle HTTP 409**  
   - If the backend returns **409**, do **not** treat it as a generic server error.  
   - **Recommended:** Show a short message like: “This request was already used with different options. Please start a new generation.” and **do not** retry with the same `requestId`.  
   - Optionally: on 409, generate a **new** `requestId` and send a **new** request with the **current** payload (so the user can get a result without re-entering everything).

4. **Retry safely**  
   - On **network/timeout errors** or **5xx**, retry the **exact same** request (same `requestId`, same body). The backend will return the cached response if the first attempt had already succeeded.  
   - Do **not** reuse a `requestId` for a different payload (different prompt, languages, or existingBoxes); that will cause 409.

5. **No change to request/response models**  
   - Request body: `requestId`, `customerId`, `prompt`, `defaultLanguage`, `targetLanguage`, `existingBoxes` (unchanged).  
   - Success response: same `GenerateBoxesResponse` as before (requestId, status, boxes, level, topic, etc.).  
   - Only new case: **409** with a `detail` string.

---

## Suggested UX

- **One requestId per “Generate” tap:** When the user taps “Generate”, create a new `requestId` and send the request. Any retries (e.g. after timeout) use the same `requestId` and same body.  
- **New tap or new options = new requestId:** If the user changes the prompt or settings and taps “Generate” again, generate a new `requestId`.  
- **409:** Tell the user to start a new generation (or automatically start one with a new `requestId` and current payload).

---

## API contract (quick reference)

| Case | Backend behavior |
|------|------------------|
| New `(customerId, requestId)` | Run workflow, return 200 + `GenerateBoxesResponse`. |
| Same `(customerId, requestId)` + same payload (exact replay/retry) | Return 200 + **cached** `GenerateBoxesResponse` (no new generation). |
| Same `(customerId, requestId)` + different payload | Return **409** + `{"detail": "Idempotency conflict: ..."}`. |
| Same customerId, different requestId | New request; 200 + normal response. |
| Different customerId, same requestId | New request (no collision); 200 + normal response. |

Request body (unchanged):  
`{ "requestId": string, "customerId": string, "prompt": string, "defaultLanguage": string, "targetLanguage": string, "existingBoxes": [...] }`

Success response (unchanged):  
200 + `GenerateBoxesResponse` (requestId, status, boxes, level, topic, userMessage, etc.).

New error response:  
**409 Conflict** — body: `{ "detail": "Idempotency conflict: this requestId was already used with a different payload for this customer." }`
