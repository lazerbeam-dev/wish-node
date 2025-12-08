
# items.py
from typing import Any, Dict, List, Optional
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
	existing_items: List[Item] = [],
	wish_title: str = "",
	ai_client: Optional[Any] = None,
	model: str = "gpt-4o-mini",
	seed: Optional[str] = None,
) -> Dict[str, Any]:
	"""
	Ask the AI to propose an item for this task completion.
	Validates the response follows a minimal schema and persists a new Item row.
	Returns the saved item as a dict.

	Raises ValueError on invalid AI output. Allows callers to mock ai.get_item_from_chatgpt.
	"""
	# default ai client to main.client if available
	if ai_client is None:
		try:
			import main as _main  # optional: your app's global client
			ai_client = getattr(_main, "client", None)
		except Exception:
			ai_client = None

	# Build prompt/context payload - keep minimal; ai handler builds the final prompt
	clean_items = [
		{
			"title": i.title,
			"description": i.description,
			"legendariness": i.legendariness,
			"tags": i.tags.split(",") if isinstance(i.tags, str) else i.tags
		}
		for i in existing_items
	]
	print(clean_items)

	ctx = {
		"wish_text": wish_title,
		"phase_title": phase_title,
		"task_text": task_text,
		"seed": seed or str(uuid4())[:8],
		"existing_items": clean_items
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

	item = out.get("item")
	if not isinstance(item, dict):
		raise ValueError("AI output missing 'item' object")

	# safe accessors
	upg = (item.get("upgrades_previous") or "")
	upg_stripped = upg.strip() if isinstance(upg, str) else ""

	title = (item.get("name") or "").strip()
	tags = item.get("tags", [])
	description = (item.get("description") or "").strip()
	print("item", item)

	now = datetime.now(timezone.utc)

	# If upgrades_previous present (non-empty / non-whitespace), attempt to replace existing item
	if upg_stripped:
		# find existing item with that title and the same wish id
		try:
			existing_row = db.query(Item).filter(
				Item.title == upg_stripped,
				Item.origin_wish_id == wish_id
			).first()
		except Exception:
			# fallback for other DB session APIs (e.g. raw connection) — try a generic query pattern
			existing_row = None

		if existing_row:
			# update in-place
			existing_row.title = title or existing_row.title
			existing_row.emoji = item.get("emoji", getattr(existing_row, "emoji", None))
			existing_row.emoji_accent = item.get("emoji_accent", getattr(existing_row, "emoji_accent", None))
			existing_row.legendariness = item.get("legendariness", getattr(existing_row, "legendariness", None))
			existing_row.description = description or existing_row.description
			# store tags as list if your model supports it; adjust if tags is a comma string in your schema
			existing_row.tags = tags or getattr(existing_row, "tags", [])
			# persist changes
			db.add(existing_row)
			db.commit()
			db.refresh(existing_row)

			saved = {
				"id": existing_row.id,
				"origin_wish_id": existing_row.origin_wish_id,
				"title": existing_row.title,
				"description": existing_row.description,
				"tags": existing_row.tags,
				"emoji": getattr(existing_row, "emoji", None),
				"emoji_accent": getattr(existing_row, "emoji_accent", None),
				"legendariness": getattr(existing_row, "legendariness", None),
			}
			return saved
		# if no match found, fall through to create a new item (intentional)

	# persist Item - create new
	new_id = str(uuid4())

	item_row = Item(
		id=new_id,
		origin_wish_id=wish_id,
		title=title,
		emoji=item.get("emoji"),
		emoji_accent=item.get("emoji_accent"),
		legendariness=item.get("legendariness"),
		description=description or f"Item: {title}",
		tags=tags or [],
	)

	db.add(item_row)
	db.commit()
	db.refresh(item_row)

	saved = {
		"id": item_row.id,
		"origin_wish_id": item_row.origin_wish_id,
		"title": item_row.title,
		"description": item_row.description,
		"tags": item_row.tags,
		"emoji": getattr(item_row, "emoji", None),
		"emoji_accent": getattr(item_row, "emoji_accent", None),
		"legendariness": getattr(item_row, "legendariness", None),
	}
	return saved

