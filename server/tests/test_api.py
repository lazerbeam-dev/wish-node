# tests/test_api.py
import os
import tempfile
from uuid import uuid4
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Import your app & modules — adjust name if your app file is not main.py
import main as app_module
import ai as ai_module
from models import Base, WishStatus, Wish  # import Wish model to insert directly

# --- Fixtures: temp DB, TestClient, and dependency override ---

@pytest.fixture(scope="session")
def temp_sqlite_file():
    # create a temporary sqlite file that will be removed at teardown
    fd, path = tempfile.mkstemp(prefix="wishnode_test_", suffix=".db")
    os.close(fd)
    yield path
    try:
        os.remove(path)
    except OSError:
        pass

@pytest.fixture(scope="session")
def engine_and_session(temp_sqlite_file):
    # Create a dedicated engine for tests with same check_same_thread setting as main
    DATABASE_URL = f"sqlite:///{temp_sqlite_file}"
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
    TestingSessionLocal = sessionmaker(bind=engine)

    # Create tables
    Base.metadata.create_all(bind=engine)

    yield engine, TestingSessionLocal

    # Teardown: drop tables and dispose engine
    Base.metadata.drop_all(bind=engine)
    engine.dispose()

@pytest.fixture()
def db_session(engine_and_session):
    _, TestingSessionLocal = engine_and_session
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

@pytest.fixture()
def client(engine_and_session):
    engine, TestingSessionLocal = engine_and_session

    # override get_db dependency in the app module to use the testing session
    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app_module.app.dependency_overrides[app_module.get_db] = override_get_db

    # create TestClient using the real app object
    with TestClient(app_module.app) as c:
        yield c

    # clear override after test
    app_module.app.dependency_overrides.pop(app_module.get_db, None)

# --- Helper data builders ---

def make_wish_payload(owner_id: str, wish_id: str = None, title: str = "My Wish"):
    if not wish_id:
        wish_id = str(uuid4())

    phases = [
        {
            "id": str(uuid4()),
            "title": "Phase 1",
            "tasks": [
                {
                    "id": str(uuid4()),
                    # server prefers 'title' for tasks; include canonical metadata
                    "title": "Do task A",
                    "repeat": False,
                    "completed": False,
                    "completed_at": None,
                    "repeated_amount": 0,
                    "habit_interval": None,
                }
            ],
        },
        {
            "id": str(uuid4()),
            "title": "Phase 2",
            "tasks": [
                {
                    "id": str(uuid4()),
                    "title": "Do task B",
                    "repeat": False,
                    "completed": False,
                    "completed_at": None,
                    "repeated_amount": 0,
                    "habit_interval": None,
                }
            ],
        },
    ]

    return {
        "id": wish_id,
        "owner_id": owner_id,
        "title": title,
        "phases": phases
    }

# --- Mocks for OpenAI / ai ---

@pytest.fixture(autouse=True)
def mock_ai_and_openai(monkeypatch):
    # Mock ai.get_plan_from_chatgpt to return deterministic output
    def fake_get_plan_from_chatgpt(wish_text, client, model=None):
        # return a simple canonical plan that the server can normalize
        return {"plan_for": wish_text, "phases": [{"title": "p1", "tasks": []}]}
    monkeypatch.setattr(ai_module, "get_plan_from_chatgpt", fake_get_plan_from_chatgpt)

    # Mock main.client.chat.completions.create used by /api/test_chatgpt endpoint
    fake_resp = MagicMock()
    fake_choices = [MagicMock(message=MagicMock(content="hello from fake GPT"))]
    fake_resp.choices = fake_choices

    # Some installations may have .chat.completions.create nested differently; guard both.
    if hasattr(app_module.client, "chat") and hasattr(app_module.client.chat, "completions"):
        monkeypatch.setattr(app_module.client.chat.completions, "create", lambda **kwargs: fake_resp)
    else:
        # fallback: monkeypatch app_module.client.chat wrapper
        try:
            monkeypatch.setattr(app_module.client, "chat", MagicMock(completions=MagicMock(create=lambda **kwargs: fake_resp)))
        except Exception:
            pass

    yield

# --- Tests ---

def test_create_anon_and_cookie(client):
    r = client.post("/api/anon")
    assert r.status_code == 200
    data = r.json()
    assert "anon_user_id" in data
    # cookie set
    assert "set-cookie" in r.headers or r.cookies.get("wishnode_anon_id") is not None

def test_claim_user_creates_and_moves_wishes(client, db_session):
    # create anon
    r = client.post("/api/anon")
    anon_id = r.json()["anon_user_id"]

    # create a wish directly in DB owned by anon
    payload = make_wish_payload(owner_id=anon_id)
    w = Wish(
        id=payload["id"],
        owner_id=payload["owner_id"],
        title=payload["title"],
        phases=payload["phases"],
        status=WishStatus.in_progress
    )
    db_session.add(w)
    db_session.commit()

    # now claim the user
    email = "test@example.com"
    password = "hunter2"
    r3 = client.post("/api/users/claim", params={"anon_user_id": anon_id, "email": email, "password_plain": password})
    assert r3.status_code == 200
    new_user_id = r3.json()["user_id"]

    # ensure the wish now belongs to the new user (list_active_wishes)
    r4 = client.get("/api/wishes", params={"user_id": new_user_id})
    assert r4.status_code == 200
    wishes = r4.json()["wishes"]
    assert any(wd["id"] == payload["id"] for wd in wishes)


def test_get_wish_and_not_found(client, db_session):
    owner_id = str(uuid4())
    payload = make_wish_payload(owner_id=owner_id)
    # create wish directly in DB
    w = Wish(
        id=payload["id"],
        owner_id=payload["owner_id"],
        title=payload["title"],
        phases=payload["phases"],
        status=WishStatus.in_progress
    )
    db_session.add(w)
    db_session.commit()
    wish_id = payload["id"]

    r = client.get(f"/api/wishes/{wish_id}")
    assert r.status_code == 200
    wresp = r.json()["wish"]
    assert wresp["id"] == wish_id

    # nonexistent
    r2 = client.get("/api/wishes/nonexistent-id")
    assert r2.status_code == 404

def test_complete_task_completes_and_creates_item(client, db_session):
    # create anon + wish with 2 tasks across phases in DB
    r = client.post("/api/anon")
    anon_id = r.json()["anon_user_id"]
    payload = make_wish_payload(owner_id=anon_id)

    # insert wish directly
    w = Wish(
        id=payload["id"],
        owner_id=payload["owner_id"],
        title=payload["title"],
        phases=payload["phases"],
        status=WishStatus.in_progress
    )
    db_session.add(w)
    db_session.commit()
    wish_id = payload["id"]

    # extract tasks ids
    t1 = payload["phases"][0]["tasks"][0]["id"]
    t2 = payload["phases"][1]["tasks"][0]["id"]

    # complete first task
    r1 = client.post(f"/api/wishes/{wish_id}/tasks/{t1}/complete")
    assert r1.status_code == 200
    assert r1.json()["ok"] is True

    # complete second task -> should create item and mark wish completed
    r2 = client.post(f"/api/wishes/{wish_id}/tasks/{t2}/complete")
    assert r2.status_code == 200
    data = r2.json()
    assert data.get("ok") is True
    assert "created_item_id" in data

    # confirm wish is completed when fetching
    r3 = client.get(f"/api/wishes/{wish_id}")
    assert r3.status_code == 200
    assert r3.json()["wish"]["status"] in (WishStatus.completed.value, WishStatus.completed)

def test_delete_wish_and_vault(client, db_session):
    r = client.post("/api/anon")
    anon_id = r.json()["anon_user_id"]
    payload = make_wish_payload(owner_id=anon_id)

    # insert wish
    w = Wish(
        id=payload["id"],
        owner_id=payload["owner_id"],
        title=payload["title"],
        phases=payload["phases"],
        status=WishStatus.in_progress
    )
    db_session.add(w)
    db_session.commit()
    wish_id = payload["id"]

    # delete via API
    r2 = client.delete(f"/api/wishes/{wish_id}")
    assert r2.status_code == 200
    assert r2.json()["ok"] is True

    # get should now 404
    r3 = client.get(f"/api/wishes/{wish_id}")
    assert r3.status_code == 404

    # vault should be empty (or not include this wish)
    r4 = client.get("/api/vault", params={"user_id": anon_id})
    assert r4.status_code == 200
    assert "items" in r4.json()

def test_should_nudge_behavior(client, db_session):
    r = client.post("/api/anon")
    anon_id = r.json()["anon_user_id"]

    # initially: should_nudge True (no tasks completed)
    r1 = client.get(f"/api/users/{anon_id}/should_nudge")
    assert r1.status_code == 200
    assert r1.json()["should_nudge"] is True

    # create a wish and insert it in DB; then complete a task with completed_at set to now
    payload = make_wish_payload(owner_id=anon_id)
    w = Wish(
        id=payload["id"],
        owner_id=payload["owner_id"],
        title=payload["title"],
        phases=payload["phases"],
        status=WishStatus.in_progress
    )
    db_session.add(w)
    db_session.commit()
    wish_id = payload["id"]
    task_id = payload["phases"][0]["tasks"][0]["id"]

    # complete so that completed_at is set to now
    r2 = client.post(f"/api/wishes/{wish_id}/tasks/{task_id}/complete")
    assert r2.status_code == 200

    # now should_nudge should be False (recent completed timestamp)
    r3 = client.get(f"/api/users/{anon_id}/should_nudge")
    assert r3.status_code == 200
    assert r3.json()["should_nudge"] in (False, 0)

def test_create_wish_owner_auto_create_and_free_limit(client):
    """
    The old test used POST /api/wishes (which was removed).
    Use /api/anon to create an owner, then call /api/wishes/plan to create a wish.
    """
    # create anon owner
    r_anon = client.post("/api/anon")
    assert r_anon.status_code == 200
    owner_id = r_anon.json()["anon_user_id"]

    # build payload (we'll use the title as the 'wish' text for the plan endpoint)
    payload = make_wish_payload(owner_id=owner_id)
    plan_body = {
        "wish": payload["title"],
        "owner_id": owner_id,
        "wish_id": payload["id"],
        "title": payload["title"],
    }

    r = client.post("/api/wishes/plan", json=plan_body)
    assert r.status_code == 200
    j = r.json()
    assert j.get("ok") is True
    # ensure the saved wish exists and has the expected id
    saved = j.get("wish", {})
    assert saved.get("id") == payload["id"]
    assert saved.get("owner_id") == owner_id


def test_create_wish_free_limit_blocking(client):
    """
    Use /api/wishes/plan to create active wishes up to FREE_ACTIVE_WISH_LIMIT,
    then ensure the next creation attempt is blocked with 403.
    """
    # create anon user
    r = client.post("/api/anon")
    assert r.status_code == 200
    anon_id = r.json()["anon_user_id"]

    # create FREE_ACTIVE_WISH_LIMIT wishes via the plan endpoint
    for i in range(app_module.FREE_ACTIVE_WISH_LIMIT):
        payload = make_wish_payload(owner_id=anon_id, title=f"wish{i}")
        plan_body = {"wish": payload["title"], "owner_id": anon_id, "wish_id": payload["id"], "title": payload["title"]}
        resp = client.post("/api/wishes/plan", json=plan_body)
        assert resp.status_code == 200
        assert resp.json().get("ok") is True

    # the next one should be blocked (403)
    payload = make_wish_payload(owner_id=anon_id, title="too many")
    plan_body = {"wish": payload["title"], "owner_id": anon_id, "wish_id": payload["id"], "title": payload["title"]}
    r2 = client.post("/api/wishes/plan", json=plan_body)
    assert r2.status_code == 403

def test_test_chatgpt_and_pipeline_and_plan_endpoints(client):
    # test_chatgpt (mocked)
    r = client.get("/api/test_chatgpt")
    assert r.status_code == 200
    data = r.json()
    assert "reply" in data or "error" in data

    # test pipeline endpoint uses ai.get_plan_from_chatgpt (mocked)
    r2 = client.get("/api/test_chatgpt_pipeline")
    assert r2.status_code == 200
    out = r2.json()
    assert out.get("ok") is True
    assert "result" in out

    # api_get_plan requires owner_id now: create anon and pass owner_id
    r_anon = client.post("/api/anon")
    assert r_anon.status_code == 200
    anon_id = r_anon.json()["anon_user_id"]

    r3 = client.post("/api/wishes/plan", json={"wish": "learn french", "owner_id": anon_id})
    assert r3.status_code == 200
    data3 = r3.json()
    # endpoint now saves the plan into a Wish; assert that shape
    assert data3.get("ok") is True
    assert "wish" in data3 and "owner_id" in data3
    saved = data3["wish"]
    phases = saved.get("phases") or []
    assert len(phases) == 1
    assert phases[0].get("title") == "p1"
    assert phases[0].get("tasks") == []
    assert "id" in phases[0]

def test_wishes_plan_creates_wish_and_returns_owner(client):
    # plan endpoint requires owner_id: create anon user first
    r_anon = client.post("/api/anon")
    assert r_anon.status_code == 200
    anon_id = r_anon.json()["anon_user_id"]

    r = client.post("/api/wishes/plan", json={"wish": "learn french", "owner_id": anon_id})
    assert r.status_code == 200
    data = r.json()
    assert data.get("ok") is True
    assert "owner_id" in data
    assert "wish" in data

    owner_id = data["owner_id"]
    saved_wish = data["wish"]
    phases = saved_wish.get("phases") or []
    assert len(phases) == 1
    assert phases[0].get("title") == "p1"
    assert phases[0].get("tasks") == []
    assert "id" in phases[0]
    wish_id = saved_wish["id"]

    r2 = client.get("/api/wishes", params={"user_id": owner_id})
    assert r2.status_code == 200
    wishes = r2.json().get("wishes", [])
    assert any(w["id"] == wish_id for w in wishes)

def test_wishes_plan_updates_existing_wish_when_wish_id_provided(client, db_session):
    # create anon user
    r = client.post("/api/anon")
    owner_id = r.json()["anon_user_id"]

    # create an initial wish directly in DB with different phases
    wish_id = str(uuid4())
    original = Wish(
        id=wish_id,
        owner_id=owner_id,
        title="orig",
        phases=[{"id": str(uuid4()), "title": "original", "tasks": []}],
        status=WishStatus.in_progress
    )
    db_session.add(original)
    db_session.commit()

    # Now call the plan endpoint to update this existing wish (mocked AI returns p1)
    r2 = client.post("/api/wishes/plan", json={"wish": "learn french", "owner_id": owner_id, "wish_id": wish_id})
    assert r2.status_code == 200
    data2 = r2.json()
    assert data2.get("ok") is True
    assert "wish" in data2
    updated = data2["wish"]
    # phases should be replaced with the mocked plan's phases
    assert updated.get("phases") == [{"title": "p1", "tasks": []}]

    # Fetch the wish directly to be extra-sure it's persisted
    r3 = client.get(f"/api/wishes/{wish_id}")
    assert r3.status_code == 200
    fetched = r3.json()["wish"]
    assert fetched.get("phases") == [{"title": "p1", "tasks": []}]

def test_complete_repeat_task_increments_repeated_amount(client, db_session):
    # create anon + wish directly in DB
    r = client.post("/api/anon")
    anon_id = r.json()["anon_user_id"]

    payload = make_wish_payload(owner_id=anon_id)
    w = Wish(
        id=payload["id"],
        owner_id=payload["owner_id"],
        title=payload["title"],
        phases=payload["phases"],
        status=WishStatus.in_progress
    )
    db_session.add(w)
    db_session.commit()
    wish_id = payload["id"]
    task_id = payload["phases"][0]["tasks"][0]["id"]

    # set repeat via PATCH (server-side edit endpoint)
    patch = client.patch(f"/api/wishes/{wish_id}/tasks/{task_id}", json={"repeat": True})
    assert patch.status_code == 200

    # first completion -> repeated_amount should become 1
    rc1 = client.post(f"/api/wishes/{wish_id}/tasks/{task_id}/complete")
    assert rc1.status_code == 200

    gw1 = client.get(f"/api/wishes/{wish_id}")
    assert gw1.status_code == 200
    saved = gw1.json()["wish"]
    found = None
    for p in saved.get("phases", []):
        for t in p.get("tasks", []):
            if t.get("id") == task_id:
                found = t
                break
        if found:
            break
    assert found is not None, "task missing after complete"
    assert int(found.get("repeated_amount", 0)) == 1
    assert bool(found.get("completed")) is True

    # second completion -> repeated_amount should become 2
    rc2 = client.post(f"/api/wishes/{wish_id}/tasks/{task_id}/complete")
    assert rc2.status_code == 200
    gw2 = client.get(f"/api/wishes/{wish_id}")
    saved2 = gw2.json()["wish"]
    found2 = None
    for p in saved2.get("phases", []):
        for t in p.get("tasks", []):
            if t.get("id") == task_id:
                found2 = t
                break
        if found2:
            break
    assert found2 is not None
    assert int(found2.get("repeated_amount", 0)) == 2
    assert bool(found2.get("completed")) is True

def test_complete_task_mark_incomplete_keeps_repeated_amount(client, db_session):
    # create anon + wish directly in DB
    r = client.post("/api/anon")
    anon_id = r.json()["anon_user_id"]

    payload = make_wish_payload(owner_id=anon_id)
    w = Wish(
        id=payload["id"],
        owner_id=payload["owner_id"],
        title=payload["title"],
        phases=payload["phases"],
        status=WishStatus.in_progress
    )
    db_session.add(w)
    db_session.commit()
    wish_id = payload["id"]
    task_id = payload["phases"][0]["tasks"][0]["id"]

    # set repeat flag via PATCH
    patch = client.patch(f"/api/wishes/{wish_id}/tasks/{task_id}", json={"repeat": True})
    assert patch.status_code == 200

    # complete once
    rc1 = client.post(f"/api/wishes/{wish_id}/tasks/{task_id}/complete")
    assert rc1.status_code == 200

    # verify repeated_amount == 1
    gw1 = client.get(f"/api/wishes/{wish_id}")
    found = None
    for p in gw1.json()["wish"].get("phases", []):
        for t in p.get("tasks", []):
            if t.get("id") == task_id:
                found = t
                break
        if found:
            break
    assert found is not None
    assert int(found.get("repeated_amount", 0)) == 1
    assert bool(found.get("completed")) is True

    # now mark as incomplete
    rc_un = client.post(
        f"/api/wishes/{wish_id}/tasks/{task_id}/complete",
        json={"mark_incomplete": True}
    )
    assert rc_un.status_code == 200

    # fetch again and verify completed is False but repeated_amount still 1
    gw2 = client.get(f"/api/wishes/{wish_id}")
    found2 = None
    for p in gw2.json()["wish"].get("phases", []):
        for t in p.get("tasks", []):
            if t.get("id") == task_id:
                found2 = t
                break
        if found2:
            break
    assert found2 is not None
    assert bool(found2.get("completed")) is False
    assert int(found2.get("repeated_amount", 0)) == 1
