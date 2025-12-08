# models.py
from sqlalchemy import (
    Column, String, Integer, DateTime, ForeignKey, Boolean, JSON, Enum
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from sqlalchemy.orm import declarative_base

import enum
Base = declarative_base()

class Tier(str, enum.Enum):
    free = "free"
    pro = "pro"
    anon = "anon"

class WishStatus(str, enum.Enum):
    in_progress = "in_progress"
    completed = "completed"
    abandoned = "abandoned"

class User(Base):
    __tablename__ = "users"
    id = Column(String, primary_key=True)
    tier = Column(Enum(Tier), default=Tier.free)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Wish(Base):
    __tablename__ = "wishes"
    id = Column(String, primary_key=True)
    owner_id = Column(String, ForeignKey("users.id"), index=True)
    title = Column(String, nullable=False)
    status = Column(Enum(WishStatus), default=WishStatus.in_progress)
    phases = Column(JSON, default=[])  # store phases/tasks as JSON
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    completed_at = Column(DateTime(timezone=True), nullable=True)
    owner = relationship("User", backref="wishes")
    deleted = Column(Boolean, default=False, nullable=False) 

class Item(Base):
    __tablename__ = "items"
    id = Column(String, primary_key=True)
    origin_wish_id = Column(String, ForeignKey("wishes.id"), nullable=False)
    title = Column(String, nullable=False)
    emoji = Column(String, nullable=True)
    emoji_accent = Column(String, nullable=True)
    legendariness = Column(Integer, nullable=False)
    description = Column(String, nullable=True)
    tags = Column(JSON, default =[])
    created_at = Column(DateTime(timezone=True), server_default=func.now())
