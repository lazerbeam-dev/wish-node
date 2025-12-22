# items.py
from typing import Any, Dict, List, Optional
from uuid import uuid4
import json
from collections import defaultdict

from models import Item
import ai


MAX_ITEMS_PER_WISH = 3


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

	CONTRACT:
	- New items allowed only until MAX_ITEMS_PER_WISH.
	- After cap is reached, upgrades are FORCED.
	- Forced upgrades select the most tag-aligned item.
	"""

	# default ai client to main.client if available
	if ai_client is None:
		try:
			import main as _main
			ai_client = getattr(_main, "client", None)
		except Exception:
			ai_client = None

	# --- GROUP EXISTING ITEMS BY core_id ---
	items_by_core = defaultdict(list)
	for i in existing_items:
		items_by_core[i.core_id].append(i)

	distinct_item_count = len(items_by_core)
	can_create_new_item = distinct_item_count < MAX_ITEMS_PER_WISH

	# --- Build minimal context for AI ---
	clean_items = [
		{
			"core_id": i.core_id,
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

	# --- INFORM AI ABOUT CAP ---
	if not can_create_new_item:
		ctx["at_item_cap"] = True
		ctx["available_core_ids"] = list(items_by_core.keys())
		#print(f"📢 Informing AI: At item cap. Must upgrade one of: {ctx['available_core_ids']}")
	else:
		ctx["at_item_cap"] = False

	# --- AI call ---
	try:
		raw = ai.get_item_from_chatgpt(ctx, client=ai_client, model=model)
	except Exception as e:
		raise RuntimeError(f"AI call failed: {e}")

	#print("AI raw output:", raw)

	# --- Parse JSON ---
	out = raw
	if isinstance(raw, str):
		out = json.loads(raw)

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

	# --- NORMALISE upgrades_previous ---
	upgrades_previous = item.get("upgrades_previous")
	if isinstance(upgrades_previous, str):
		upgrades_previous = upgrades_previous.strip()
	if upgrades_previous in ("", "null", "None"):
		upgrades_previous = None

	# --- DETERMINE IF THIS IS AN UPGRADE ---
	# Check if AI is trying to upgrade (upgrades_previous is set AND matches an existing core_id)
	is_ai_upgrading = upgrades_previous and upgrades_previous in items_by_core
	
	# Check if AI is trying to create new but we're at cap
	is_forced_upgrade = not can_create_new_item and not is_ai_upgrading

	# --- HARD CAP ENFORCEMENT ---
	if is_forced_upgrade:
		# AI tried to create new item but we're at cap
		# Choose the most tag-aligned existing item to upgrade
		new_tags = tags or []
		
		best_core_id = None
		best_overlap = -1
		
		for candidate_core_id, candidate_items in items_by_core.items():
			# Get the latest version of this item
			candidate = max(candidate_items, key=lambda x: x.legendariness)
			candidate_tags = candidate.tags or []
			
			overlap = tag_overlap_ratio(candidate_tags, new_tags)
			if overlap > best_overlap:
				best_overlap = overlap
				best_core_id = candidate_core_id
		
		target_core_id = best_core_id or list(items_by_core.keys())[0]
		
		#print(f"⚠️ FORCED UPGRADE: AI tried to create new item '{core_id}', but cap reached. Upgrading most similar item '{target_core_id}' (overlap: {best_overlap:.2f}).")
		
		core_id = target_core_id
		upgrades_previous = target_core_id

	# --- LOOK UP UPGRADE TARGET ---
	upgrade_target = None
	if upgrades_previous:
		upgrade_target = (
			db.query(Item)
			.filter(
				Item.origin_wish_id == wish_id,
				Item.core_id == upgrades_previous,
			)
			.first()
		)

	# --- DECIDE IF WE SHOULD UPGRADE ---
	should_upgrade = False

	if upgrade_target:
		if is_forced_upgrade:
			# Always upgrade when forced
			should_upgrade = True
		elif is_ai_upgrading:
			# AI explicitly said to upgrade - trust the AI's decision
			should_upgrade = True
			#print(f"✅ AI chose to upgrade '{upgrades_previous}'")

	# --- UPGRADE IN PLACE ---
	if should_upgrade:
		#print(f"✅ UPGRADING item '{upgrade_target.core_id}': {upgrade_target.title} → {title}")
		
		existing_row = upgrade_target

		existing_row.title = title or existing_row.title
		existing_row.description = description or existing_row.description
		existing_row.tags = tags or existing_row.tags
		existing_row.emoji = emoji or existing_row.emoji
		existing_row.emoji_accent = emoji_accent or existing_row.emoji_accent

		if legendariness is not None:
			existing_row.legendariness = max(
				existing_row.legendariness,
				legendariness,
			)

		db.add(existing_row)
		db.commit()
		db.refresh(existing_row)

		return serialize_item(existing_row)

	# --- CREATE NEW ITEM (only possible if under cap) ---
	if not can_create_new_item:
		raise RuntimeError(
			f"Cannot create new item '{core_id}'. Already at {MAX_ITEMS_PER_WISH} item cap. "
			f"This should have been caught earlier."
		)
	
	#print(f"🆕 CREATING NEW item '{core_id}': {title}")
	
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
	db.commit()
	db.refresh(new_row)

	return serialize_item(new_row)


def tag_overlap_ratio(tags_a, tags_b):
	if not tags_a or not tags_b:
		return 0.0
	set_a = set(t.lower() for t in tags_a)
	set_b = set(t.lower() for t in tags_b)
	return len(set_a & set_b) / max(len(set_a), 1)


def serialize_item(item: Item) -> Dict[str, Any]:
	return {
		"id": item.id,
		"core_id": item.core_id,
		"origin_wish_id": item.origin_wish_id,
		"title": item.title,
		"description": item.description,
		"tags": item.tags,
		"emoji": item.emoji,
		"emoji_accent": item.emoji_accent,
		"legendariness": item.legendariness,
	}