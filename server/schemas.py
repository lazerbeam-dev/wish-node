# schemas.py
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

class TaskModel(BaseModel):
    id: str
    text: str
    habit_interval: Optional[str] = None  # daily|weekly|null
    completed: bool = False
    completed_at: Optional[datetime] = None
    completed_amount: Optional[int]

class PhaseModel(BaseModel):
    id: str
    title: str
    tasks: List[TaskModel] = []

class WishCreate(BaseModel):
    id: str
    owner_id: str
    title: str
    phases: List[PhaseModel] = []

class ItemOut(BaseModel):
    id: str
    origin_wish_id: str
    emoji: str
    emoji_accent: str
    title: str
    description: Optional[str]
    legendariness: int
    tags: List[str]
    created_at: datetime
