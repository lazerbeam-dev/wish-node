import os
from uuid import uuid4
import sys
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from passlib.context import CryptContext
from dotenv import load_dotenv 
from models import User, Tier
load_dotenv()
# ----------------------------
# Config
# ----------------------------


DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
	raise RuntimeError("DATABASE_URL must be set")

ADMIN_EMAIL = os.getenv("ADMIN_EMAIL")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD")

if not ADMIN_EMAIL or not ADMIN_PASSWORD:
	raise RuntimeError("Set ADMIN_EMAIL and ADMIN_PASSWORD env vars")

# ----------------------------
# Setup
# ----------------------------

engine = create_engine(
	DATABASE_URL,
	pool_pre_ping=True,
	future=True,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

pwd_context = CryptContext(
	schemes=["argon2"],
	deprecated="auto",
)


# ----------------------------
# Create admin
# ----------------------------

db = SessionLocal()

try:
	existing = db.query(User).filter(User.email == ADMIN_EMAIL).first()
	if existing:
		raise RuntimeError(f"User with email {ADMIN_EMAIL} already exists")

	admin = User(
		id=str(uuid4()),
		email=ADMIN_EMAIL,
		password_hash=pwd_context.hash(ADMIN_PASSWORD),
		role="admin",
		tier=Tier.pro,  # tier doesn't matter for admin
	)

	db.add(admin)
	db.commit()

	print("✅ Admin user created")
	print("   Email:", ADMIN_EMAIL)

finally:
	db.close()
