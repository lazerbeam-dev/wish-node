import os, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

#tests/test_items.py
import os
import tempfile
import json
from uuid import uuid4
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# import the helper and modules
import items as items_module
import ai as ai_module
from models import Base, Item  # Item must be your SQLAlchemy model

# --- fixtures: temp sqlite engine/session ---
@pytest.fixture(scope="session")
def temp_db_path():
    fd, p = tempfile.mkstemp(prefix="wishnode_items_test_", suffix=".db")
    os.close(fd)
    yield p
    try:
        os.remove(p)
    except OSError:
        pass

@pytest.fixture(scope="session")
def engine_and_session(temp_db_path):
    DATABASE_URL = f"sqlite:///{temp_db_path}"
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
    TestingSessionLocal = sessionmaker(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield engine, TestingSessionLocal
    Base.metadata.drop_all(bind=engine)
    engine.dispose()

@pytest.fixture()
def db_session(engine_and_session):
    _, TestingSessionLocal = engine_and_session
    s = TestingSessionLocal()
    try:
        yield s
    finally:
        s.close()

# --- Tests ---
def test_create_item_from_valid_ai(monkeypatch, db_session, capsys):
    # Fake AI returns a dict (could also return JSON string)
    fake_ai_output = {
        "action": "new_item",
        "item": {
            "title": "Stone of First Step",
            "archetype": "Stone",
            "tier": "wood",
            "rarity": "common",
            "tags": ["beginning", "movement"],
            "description": "Your first step hardened into a stone."
        }
    }

    def fake_get_item_from_chatgpt(ctx, client=None, model=None):
        # print is useful while iterating -- tests will capture
        print("FAKE AI called with ctx:", ctx)
        return fake_ai_output

    monkeypatch.setattr(ai_module, "get_item_from_chatgpt", fake_get_item_from_chatgpt)

    saved = items_module.create_item_from_ai(
        db=db_session,
        user_id="user-x",
        wish_id="wish-x",
        phase_title="Phase One",
        task_text="Do task A",
        ai_client=None,
        model="test-model",
        seed="seed-1",
    )

    # The test prints the raw AI output; capture & show it
    captured = capsys.readouterr()
    assert "AI raw output" in captured.out

    # validate returned shape
    assert saved["origin_wish_id"] == "wish-x"
    assert saved["title"] == "Stone of First Step"
    # ensure the item was persisted in DB
    db_item = db_session.query(Item).filter(Item.id == saved["id"]).first()
    assert db_item is not None
    assert db_item.title == "Stone of First Step"

def test_create_item_from_ai_with_json_string(monkeypatch, db_session, capsys):
    # AI returns a JSON string (exercise parser)
    ai_payload = {
        "action": "new_item",
        "item": {
            "title": "Rune of Repetition",
            "archetype": "Rune",
            "tier": "wood",
            "rarity": "uncommon",
            "tags": ["habit", "repeat"],
            "description": "Forged by repetition."
        }
    }
    def fake_get_item_from_chatgpt(ctx, client=None, model=None):
        print("FAKE AI (string) called with ctx:", ctx)
        return json.dumps(ai_payload)

    monkeypatch.setattr(ai_module, "get_item_from_chatgpt", fake_get_item_from_chatgpt)

    saved = items_module.create_item_from_ai(
        db=db_session,
        user_id="user-y",
        wish_id="wish-y",
        phase_title="Phase Two",
        task_text="Repeat A",
        ai_client=None,
        model="test-model",
        seed="seed-2",
    )

    captured = capsys.readouterr()
    assert "AI raw output" in captured.out
    assert saved["title"] == "Rune of Repetition"
    db_item = db_session.query(Item).filter(Item.id == saved["id"]).first()
    assert db_item is not None
    assert db_item.title == "Rune of Repetition"
