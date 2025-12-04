
# items.py
from typing import Any, Dict, Optional
from uuid import uuid4
from datetime import datetime, timezone
import json

# import your models and ai helper
from models import Item  # assumes Item model exists like in main.create_item usage
import ai
from openai import OpenAI  # type: ignore
import traceback

# Example: accept the OpenAI client but default to the one from main if you prefer
def create_item_from_ai(
    db,
    user_id: str,
    wish_id: str,
    phase_title: str,
    task_text: str,
    ai_client: Optional[Any] = None,
    model: str = "gpt-4o-mini",
    seed: Optional[str] = None,
    # a simple whitelist for tiers/rarities/archetypes to coerce invalid AI output:
    allowed_tiers: Optional[set] = None,
    allowed_rarities: Optional[set] = None,
) -> Dict[str, Any]:
    """
    Ask the AI to propose an item for this task completion.
    Validates the response follows a minimal schema and persists a new Item row.
    Returns the saved item as a dict.

    Raises ValueError on invalid AI output. Allows callers to mock ai.get_item_from_chatgpt.
    """
    # Use a specific ai helper function name - tests will monkeypatch ai.get_item_from_chatgpt
    if ai_client is None:
        # ai.get_item_from_chatgpt may use the global client internally (your main.client)
        ai_client = None

    # Build prompt/context payload - keep minimal; ai handler builds the final prompt
    ctx = {
        "user_id": user_id,
        "wish_id": wish_id,
        "phase_title": phase_title,
        "task_text": task_text,
        "seed": seed or str(uuid4())[:8],
    }

    # Call AI helper (tests should monkeypatch ai.get_item_from_chatgpt)
    try:
        raw = ai.get_item_from_chatgpt(ctx, client=ai_client, model=model)
    except Exception as e:
        # bubble up a clear error for tests/operations
        raise RuntimeError(f"AI call failed: {e}")

    # For debugging / iterative work, print raw AI output (as requested)
    print("AI raw output:", raw)

    # if the AI returned a JSON string, try parse it
    out = raw
    if isinstance(raw, str):
        try:
            out = json.loads(raw)
        except Exception:
            # leave as-is for validation failure downstream
            out = raw

    # Basic validation of expected schema:
    # Expect dict with at least: action == "new_item" and item object with title, archetype, tier, rarity, tags, description
    if not isinstance(out, dict):
        raise ValueError("AI output is not a JSON object/dict")

    action = out.get("action")
    if action != "new_item":
        # For this initial helper we only create new items
        raise ValueError("AI output action is not 'new_item'")

    item = out.get("item")
    if not isinstance(item, dict):
        raise ValueError("AI output missing 'item' object")

    title = (item.get("title") or "").strip()
    archetype = (item.get("archetype") or "").strip()
    tier = (item.get("tier") or "").strip()
    rarity = (item.get("rarity") or "").strip()
    tags = item.get("tags", [])
    description = (item.get("description") or "").strip()

    if not title:
        raise ValueError("Item missing title")
    if not archetype:
        raise ValueError("Item missing archetype")
    if not tier:
        raise ValueError("Item missing tier")
    if not rarity:
        raise ValueError("Item missing rarity")
    if not isinstance(tags, list):
        raise ValueError("Item.tags must be a list")
    if not description:
        # allow short description but not empty
        description = title

    # simple whitelist coercion if provided
    if allowed_tiers:
        if tier not in allowed_tiers:
            # coerce to 'wood' fallback
            tier = "wood"
    if allowed_rarities:
        if rarity not in allowed_rarities:
            rarity = "common"

    # persist Item - keep shape consistent with your current Item model used in /complete
    new_id = str(uuid4())
    now = datetime.now(timezone.utc)

    # Item model in your code previously created like:
    # Item(id=str(uuid4()), origin_wish_id=wish.id, title=wish.title, summary=..., skills=[], assets=[], buff_tags=[])
    # We'll reuse fields that exist there, and tuck archetype/tier/rarity/tags into summary/metadata if model is small.
    # Prefer to set fields that definitely exist to avoid ORM errors.
    item_row = Item(
        id=new_id,
        origin_wish_id=wish_id,
        title=title,
        summary=description or f"Item: {title}",
        skills=item.get("skills", []),
        assets=item.get("assets", []),
        buff_tags=tags or [],
    )

    # If model has metadata or JSON field, try to set it (safe-guarded)
    try:
        if hasattr(item_row, "metadata"):
            item_row.metadata = {
                "archetype": archetype,
                "tier": tier,
                "rarity": rarity,
                "ai_context": ctx,
                "ai_raw": out,
            }
    except Exception:
        # ignore fail to set optional metadata if model doesn't support it
        pass

    db.add(item_row)
    db.commit()
    db.refresh(item_row)

    # canonical representation to return
    saved = {
        "id": item_row.id,
        "origin_wish_id": item_row.origin_wish_id,
        "title": item_row.title,
        "summary": item_row.summary,
        "tags": getattr(item_row, "buff_tags", []),
        "metadata": getattr(item_row, "metadata", None),
    }
    return saved

