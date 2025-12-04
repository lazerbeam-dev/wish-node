import json
import re
from pathlib import Path
from typing import Any, Dict, Optional

PLAN_PROMPT_PATH = Path("openai/plan_prompt")
PLAN_STRUCTURE_PATH = Path("openai/plan_structure.json")
ITEM_PROMPT_PATH = Path("openai/item_prompt")
ITEM_STRUCTURE_PATH = Path("openai/item_structure.json")

def _load_file_text(p: Path) -> str:
    if not p.exists():
        raise FileNotFoundError(f"Required file not found: {p}")
    return p.read_text(encoding="utf-8")

def _strip_markdown_fences(text: str) -> str:
    """
    If text contains a code fence (``` or ```json), return inner content.
    If multiple fences present, returns the first that looks like JSON.
    """
    # find all code fences
    fence_pattern = re.compile(r"```(?:json)?\n?(.*?)```", re.DOTALL | re.IGNORECASE)
    matches = fence_pattern.findall(text)
    for m in matches:
        candidate = m.strip()
        # quick check: must start with { or [
        if candidate and candidate[0] in ("{", "["):
            return candidate
    return text

def _extract_json_from_text(text: str) -> Optional[str]:
    """
    Try a sequence of extraction strategies to return a JSON substring or None:
      1. If the whole text is JSON, return it.
      2. If there's a markdown code fence with JSON, return the fence content.
      3. Balanced-brace scan (original approach) to find first {...} or [...].
      4. Give up and return None.
    """
    if not text:
        return None

    # 0) Trim whitespace
    text = text.strip()

    # 1) Quick parse if whole text is JSON
    try:
        json.loads(text)
        return text
    except Exception:
        pass

    # 2) Try to extract from markdown fences first (```json ... ``` or ```)
    fence_extracted = _strip_markdown_fences(text)
    if fence_extracted is not text:
        try:
            json.loads(fence_extracted)
            return fence_extracted
        except Exception:
            # fallthrough to brace scan if fence content isn't valid JSON
            pass

    # 3) Balanced-brace scan (robust for JSON embedded in prose)
    patterns = ["{", "["]
    for p0 in patterns:
        start_positions = [m.start() for m in re.finditer(re.escape(p0), text)]
        for start in start_positions:
            stack = []
            for i in range(start, len(text)):
                ch = text[i]
                if ch == "{":
                    stack.append("{")
                elif ch == "[":
                    stack.append("[")
                elif ch == "}":
                    if not stack or stack[-1] not in ("{",):
                        break
                    stack.pop()
                elif ch == "]":
                    if not stack or stack[-1] not in ("[",):
                        break
                    stack.pop()
                if not stack:
                    candidate = text[start:i+1].strip()
                    # quick validation
                    try:
                        json.loads(candidate)
                        return candidate
                    except Exception:
                        # if candidate fails, continue scanning for next possible
                        break
    return None

def _safe_parse_json_from_assistant(assistant_text: str) -> Optional[Dict[str, Any]]:
    """
    Try to parse JSON from assistant text using extraction helpers.
    Returns parsed object or None.
    """
    # direct parse
    try:
        return json.loads(assistant_text)
    except Exception:
        pass

    # try extraction
    candidate = _extract_json_from_text(assistant_text)
    if candidate:
        try:
            return json.loads(candidate)
        except Exception:
            return None
    return None

def get_plan_from_chatgpt(wish: str, client: Any, model: str = "gpt-4o-mini", max_tokens: int = 1200) -> Dict[str, Any]:
    """
    Generate a structured plan from ChatGPT given a 'wish' string.

    Returns a dict:
      { "ok": True, "plan": <parsed JSON>, "raw": <assistant text>, "prompt": <final prompt> }
    or on parse failure:
      { "ok": False, "plan": None, "raw": <assistant text>, "prompt": <final prompt>, "error": <desc> }
    """
    prompt_template = _load_file_text(PLAN_PROMPT_PATH)
    structure_text = _load_file_text(PLAN_STRUCTURE_PATH)

    if "{{wish}}" in prompt_template:
        final_prompt = prompt_template.replace("{{wish}}", wish)
    else:
        final_prompt = f"{prompt_template}\n\nWish: {wish}"

    final_prompt = (
        final_prompt
        + "\n\nStructure definition (producer must output a JSON object that matches this structure):\n"
        + structure_text
        + "\n\nIMPORTANT: Return only valid JSON that conforms to the structure above. "
        + "If you cannot fully fill a field, return it as null or empty list/object as appropriate."
    )

    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": final_prompt}],
            max_tokens=max_tokens,
        )
    except Exception as exc:
        # bubble up client/network error — caller likely wants to treat as failure
        raise Exception(f"OpenAI request failed: {exc}")

    # extract assistant text robustly
    try:
        assistant_text = resp.choices[0].message.content
    except Exception:
        assistant_text = getattr(resp.choices[0].message, "content", str(resp))

    parsed = _safe_parse_json_from_assistant(assistant_text)

    if parsed is None:
        # Do NOT raise here — return a structured failure so caller can inspect raw text.
        sample = assistant_text
        if len(sample) > 2000:
            sample = sample[:2000] + " ...[truncated]"
        return {
            "ok": False,
            "plan": None,
            "raw": assistant_text,
            "prompt": final_prompt,
            "error": "AI returned unparseable JSON",
            "sample": sample,
        }

    return {"ok": True, "plan": parsed, "raw": assistant_text, "prompt": final_prompt}

def get_item_from_chatgpt(
    context: Dict[str, Any],
    client: Any,
    model: str = "gpt-4o-mini",
    max_tokens: int = 600,
) -> Dict[str, Any]:
    """
    Generate an item (or item upgrade) via ChatGPT.

    Returns:
      { "ok": True, "item": <parsed JSON>, "raw": <assistant text>, "prompt": <final prompt> }
    or on parse failure:
      { "ok": False, "item": None, "raw": <assistant text>, "prompt": <final prompt>, "error": <desc> }
    """
    prompt_template = _load_file_text(ITEM_PROMPT_PATH)
    structure_text = _load_file_text(ITEM_STRUCTURE_PATH)

    ctx_json = json.dumps(context, ensure_ascii=False, indent=2)

    if "{{context}}" in prompt_template:
        final_prompt = prompt_template.replace("{{context}}", ctx_json)
    elif "{{wish}}" in prompt_template:
        final_prompt = prompt_template.replace("{{wish}}", context.get("wish_title", context.get("wish", "")))
        final_prompt += "\n\nContext:\n" + ctx_json
    else:
        final_prompt = prompt_template + "\n\nContext:\n" + ctx_json

    final_prompt = (
        final_prompt
        + "\n\nItem structure (producer must output only valid JSON that matches this structure):\n"
        + structure_text
        + "\n\nIMPORTANT: Return only valid JSON (no surrounding explanation). "
        + "If a field cannot be filled, return null or an empty structure as appropriate."
    )

    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": final_prompt}],
            max_tokens=max_tokens,
        )
    except Exception as exc:
        raise Exception(f"OpenAI request failed: {exc}")

    try:
        assistant_text = resp.choices[0].message.content
    except Exception:
        assistant_text = getattr(resp.choices[0].message, "content", str(resp))

    parsed = _safe_parse_json_from_assistant(assistant_text)
    if parsed is None:
        sample = assistant_text
        if len(sample) > 2000:
            sample = sample[:2000] + " ...[truncated]"
        return {
            "ok": False,
            "item": None,
            "raw": assistant_text,
            "prompt": final_prompt,
            "error": "AI returned unparseable JSON",
            "sample": sample,
        }

    return {"ok": True, "item": parsed, "raw": assistant_text, "prompt": final_prompt}
