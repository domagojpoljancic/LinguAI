"""LangGraph node: LinguAI language-learning agent."""

from dotenv import load_dotenv
from langchain_openai import ChatOpenAI
from langchain_core.messages import SystemMessage, HumanMessage

from app.state import AgentState

load_dotenv()

# Rely on OPENAI_API_KEY from env (loaded via dotenv). Timeout to avoid hanging requests.
LLM = ChatOpenAI(model="gpt-4o-mini", request_timeout=60)

SYSTEM_PROMPT = """You are LinguAI, a friendly language-learning assistant. Help users with:
- Vocabulary: definitions, synonyms, and usage
- Grammar: clear, short explanations and corrections
- Translation nuance: when direct translation fails, explain meaning and tone
- Example sentences: natural, level-appropriate examples
Keep answers concise and pedagogically useful. Use simple language unless the user asks for advanced content."""

FALLBACK_MESSAGE = "Sorry, I couldn't process your request right now. Please check your connection and try again."


def linguai_agent(state: AgentState) -> dict:
    """
    Process user input with the LinguAI LLM and return the assistant response.
    Updates state with the model's reply or a fallback on error.
    """
    user_input = state.get("user_input", "").strip() or "Hello"
    history = state.get("messages") or []
    # Build [system, ...history, current] so we can add conversation history later.
    messages = [SystemMessage(content=SYSTEM_PROMPT), *history, HumanMessage(content=user_input)]
    try:
        result = LLM.invoke(messages)
        return {"response": result.content if hasattr(result, "content") else str(result)}
    except Exception:
        return {"response": FALLBACK_MESSAGE}
