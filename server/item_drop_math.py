# item_drop_math.py
"""
Item drop math for Wishnode — golden-ticket decision only.

This module decides whether a task completion should produce a "golden ticket"
(i.e. an item/upgrade event). What the golden ticket yields is outside this module.

Pure functions given DecisionContext and an injected rng (random.Random) make it
easy to unit test deterministically.

Usage example:
    from item_drop_math import ItemDropMath, DecisionContext
    ctx = DecisionContext(...)

    rng = random.Random(1234)
    result = ItemDropMath.decide_award(ctx, rng=rng)
    if result["award"]:
        # call item generator (AI) and persist result
"""

from dataclasses import dataclass
from typing import Dict, Any, List, Optional
import random

# -------------------------
# Configurable constants
# -------------------------
# Base probability for an "average" non-repeat, medium importance task
BASE_PROB = 0.15  # 15%

# Importance multipliers
IMPORTANCE_MULTIPLIERS = {
    "low": 0.5,
    "medium": 1.0,
    "high": 2.0,
    "critical": 4.0,
}

# Repeat tasks base multiplier (reduces drop frequency for recurring tasks)
REPEAT_MULTIPLIER = 0.3

# Multipliers applied when repeated_amount is near milestone numbers
MILESTONE_NEARBY_MULTIPLIER = 3.0

# Milestone numbers (the engine treats being near these as worthy of extra chance)
MILESTONE_NUMBERS = [5, 10, 25, 50, 100]

# How close to milestone counts as "near"
MILESTONE_DELTA = 2  # ±2

# Drought smoothing: if many misses, increase chance gradually
DROUGHT_THRESHOLDS = [
    (15, 1.5),   # >15 misses -> x1.5
    (30, 2.0),   # >30 misses -> x2
]
# If misses exceed this, make a guaranteed "soft" drop
DROUGHT_HARD_GUARANTEE = 60

# Flood suppression: if many recent drops, reduce probability
FLOOD_RECENT_TASKS = 3
FLOOD_SUPPRESSION = 0.33  # divide prob if user got item recently

# A soft cap on maximum effective probability to avoid flooding
MAX_EFFECTIVE_PROB = 0.95

# -------------------------
# Data structures
# -------------------------

@dataclass
class DecisionContext:
    """
    Context used when computing drop probability.

    - user_id, wish_id, task_id, task_title: identifiers
    - is_repeat: whether task is a repeating/habit task
    - repeated_amount: how many times the repeating task has been completed historically
    - importance: "low"/"medium"/"high"/"critical" (client or AI can set)
    - recent_misses: number of task completions without a drop for this user (hidden state)
    - got_item_recently: whether the user got an item in the last FLOOD_RECENT_TASKS completions
    - tags, existing_items: optional for future heuristics (not used by math now)
    """
    user_id: str
    wish_id: str
    task_id: str
    task_title: str
    is_repeat: bool = False
    repeated_amount: int = 0
    importance: str = "medium"  # one of low/medium/high/critical
    recent_misses: int = 0  # hidden count of tasks since last award for this user
    got_item_recently: bool = False  # whether user got an item in last FLOOD_RECENT_TASKS
    tags: Optional[List[str]] = None
    existing_items: Optional[List[Dict[str, Any]]] = None

# -------------------------
# Helper functions
# -------------------------


def importance_multiplier(importance: str) -> float:
    return IMPORTANCE_MULTIPLIERS.get(importance, IMPORTANCE_MULTIPLIERS["medium"])


def repeat_multiplier(is_repeat: bool) -> float:
    return REPEAT_MULTIPLIER if is_repeat else 1.0


def is_near_milestone(repeated_amount: int) -> bool:
    if repeated_amount <= 0:
        return False
    for m in MILESTONE_NUMBERS:
        if abs(repeated_amount - m) <= MILESTONE_DELTA:
            return True
    return False


def drought_multiplier(recent_misses: int) -> float:
    if recent_misses >= DROUGHT_HARD_GUARANTEE:
        return float("inf")  # signal to guarantee award in wrapper
    mult = 1.0
    for thresh, m in DROUGHT_THRESHOLDS:
        if recent_misses > thresh:
            mult = m
    return mult


def clamp_prob(p: float) -> float:
    if p < 0:
        return 0.0
    if p > MAX_EFFECTIVE_PROB:
        return MAX_EFFECTIVE_PROB
    return p


# -------------------------
# Public API
# -------------------------


class ItemDropMath:
    """
    Item drop decision logic.

    All methods are deterministic given DecisionContext and an injected RNG.
    """

    @staticmethod
    def compute_base_probability(ctx: DecisionContext) -> float:
        """
        Compute the raw probability before RNG that this task completion should award.
        Combines base, importance, repeat modifier, milestone multiplier, drought/flood.
        Does NOT perform RNG or produce final award decision.
        Returns float in [0, MAX_EFFECTIVE_PROB] or float('inf') for drought guarantee.
        """
        p = BASE_PROB
        p *= importance_multiplier(ctx.importance)
        p *= repeat_multiplier(ctx.is_repeat)

        # Milestone bump for repeating tasks (and optionally for important singles)
        if ctx.is_repeat and is_near_milestone(ctx.repeated_amount):
            p *= MILESTONE_NEARBY_MULTIPLIER

        if not ctx.is_repeat and ctx.importance in ("high", "critical"):
            p *= 1.15

        # drought smoothing - special guarantee marker possible
        drought_mult = drought_multiplier(ctx.recent_misses)
        if drought_mult == float("inf"):
            return float("inf")
        p *= drought_mult

        # flood suppression
        if ctx.got_item_recently:
            p *= FLOOD_SUPPRESSION

        return clamp_prob(p)

    @staticmethod
    def decide_award(
        ctx: DecisionContext,
        rng: Optional[random.Random] = None,
    ) -> Dict[str, Any]:
        """
        Decide whether to award (golden ticket) on this completion.

        Returns:
            {
                "award": bool,
                "prob": float,       # the computed probability used (1.0 for guaranteed drought)
                "reason": str,       # text like "roll_success", "drought_guarantee", "roll_failed"
                "roll": float,       # the random roll (0..1), useful for logging/tests
            }
        """
        if rng is None:
            rng = random.Random()

        p = ItemDropMath.compute_base_probability(ctx)

        # drought guarantee
        if p == float("inf"):
            return {"award": True, "prob": 1.0, "reason": "drought_guarantee", "roll": 0.0}

        roll = rng.random()
        awarded = roll < p

        if awarded:
            return {"award": True, "prob": p, "reason": f"roll_success", "roll": roll}
        else:
            return {"award": False, "prob": p, "reason": f"roll_failed", "roll": roll}

    @staticmethod
    def should_force_on_phase_completion(ctx: DecisionContext) -> bool:
        """
        Helper whether to treat a phase completion as a near-guarantee condition.
        Caller may use this to bump recent_misses or call decide_award with different ctx.
        """
        if ctx.importance in ("high", "critical"):
            return True
        if ctx.is_repeat and ctx.repeated_amount >= 5:
            return True
        return False


# -------------------------
# CLI demo (not run on import)
# -------------------------
if __name__ == "__main__":
    import pprint

    rng = random.Random()
    ctx = DecisionContext(
        user_id="u1",
        wish_id="w1",
        task_id="t1",
        task_title="Finish chapter",
        is_repeat=False,
        repeated_amount=9,
        importance="high",
        recent_misses=10,
        got_item_recently=False,
    )
    pprint.pprint(ItemDropMath.decide_award(ctx, rng=rng))
