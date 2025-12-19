
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
	Ask the AI to propose or upgrade an item for this task completion.
	Uses core_id as the canonical identity to avoid duplicates and race conditions.
	"""

	# default ai client to main.client if available
	if ai_client is None:
		try:
			import main as _main
			ai_client = getattr(_main, "client", None)
		except Exception:
			ai_client = None

	# Build minimal context for AI
	clean_items = [
		{
			"core_id": getattr(i, "core_id", None),
			"title": i.title,
			"description": i.description,
			"legendariness": i.legendariness,
			"tags": i.tags.split(",") if isinstance(i.tags, str) else i.tags,
		}
		for i in existing_items
	]

	ctx = {
		"wish_text": wish_title,
		"phase_title": phase_title,
		"task_text": task_text,
		"seed": seed or str(uuid4())[:8],
		"existing_items": clean_items,
	}

	# --- AI call ---
	try:
		raw = ai.get_item_from_chatgpt(ctx, client=ai_client, model=model)
	except Exception as e:
		raise RuntimeError(f"AI call failed: {e}")

	print("AI raw output:", raw)

	# Parse JSON if needed
	out = raw
	if isinstance(raw, str):
		try:
			out = json.loads(raw)
		except Exception:
			raise ValueError("AI output was not valid JSON")

	if not isinstance(out, dict):
		raise ValueError("AI output is not a JSON object")

	item = out.get("item")
	if not isinstance(item, dict):
		raise ValueError("AI output missing 'item' object")

	# --- REQUIRED FIELDS ---
	core_id = (item.get("core_id") or "").strip()
	if not core_id:
		raise ValueError("AI item missing core_id")

	title = (item.get("name") or "").strip()
	description = (item.get("description") or "").strip()
	tags = item.get("tags") or []
	emoji = item.get("emoji")
	emoji_accent = item.get("emoji_accent")
	legendariness = item.get("legendariness")

	# --- LOOK UP EXISTING ITEM BY core_id ---
	existing_row = (
		db.query(Item)
		.filter(
			Item.origin_wish_id == wish_id,
			Item.core_id == core_id,
		)
		.first()
	)

	if existing_row:
		# --- UPGRADE IN PLACE ---
		existing_row.title = title or existing_row.title
		existing_row.description = description or existing_row.description
		existing_row.tags = tags or existing_row.tags
		existing_row.emoji = emoji or existing_row.emoji
		existing_row.emoji_accent = emoji_accent or existing_row.emoji_accent
		existing_row.legendariness = (
			legendariness
			if legendariness is not None
			else existing_row.legendariness
		)

		db.add(existing_row)
		db.commit()
		db.refresh(existing_row)

		return {
			"id": existing_row.id,
			"core_id": existing_row.core_id,
			"origin_wish_id": existing_row.origin_wish_id,
			"title": existing_row.title,
			"description": existing_row.description,
			"tags": existing_row.tags,
			"emoji": existing_row.emoji,
			"emoji_accent": existing_row.emoji_accent,
			"legendariness": existing_row.legendariness,
		}

	# --- CREATE NEW ITEM ---
	new_row = Item(
		id=str(uuid4()),
		core_id=core_id,
		origin_wish_id=wish_id,
		title=title,
		description=description or f"Item: {title}",
		tags=tags or [],
		emoji=emoji,
		emoji_accent=emoji_accent,
		legendariness=legendariness,
	)

	db.add(new_row)

	try:
		db.commit()
	except Exception:
		# In case of race condition + unique constraint:
		db.rollback()
		existing_row = (
			db.query(Item)
			.filter(
				Item.origin_wish_id == wish_id,
				Item.core_id == core_id,
			)
			.first()
		)
		if existing_row:
			return {
				"id": existing_row.id,
				"core_id": existing_row.core_id,
				"origin_wish_id": existing_row.origin_wish_id,
				"title": existing_row.title,
				"description": existing_row.description,
				"tags": existing_row.tags,
				"emoji": existing_row.emoji,
				"emoji_accent": existing_row.emoji_accent,
				"legendariness": existing_row.legendariness,
			}
		raise

	db.refresh(new_row)

	return {
		"id": new_row.id,
		"core_id": new_row.core_id,
		"origin_wish_id": new_row.origin_wish_id,
		"title": new_row.title,
		"description": new_row.description,
		"tags": new_row.tags,
		"emoji": new_row.emoji,
		"emoji_accent": new_row.emoji_accent,
		"legendariness": new_row.legendariness,
	}

