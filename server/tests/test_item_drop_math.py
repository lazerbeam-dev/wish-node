# tests/test_item_drop_math.py
import random
import math

import pytest

from item_drop_math import (
    ItemDropMath,
    DecisionContext,
    BASE_PROB,
    DROUGHT_HARD_GUARANTEE,
    DROUGHT_THRESHOLDS,
)


def test_non_drought_prob_and_roll_consistency():
    """
    Non-drought case: compute prob, run decide_award with a stable RNG,
    and verify:
      - returned prob matches compute_base_probability
      - award == (roll < prob)
    This avoids depending on a particular RNG outcome.
    """
    ctx = DecisionContext(
        user_id="u1",
        wish_id="w1",
        task_id="t1",
        task_title="Test task",
        is_repeat=False,
        repeated_amount=0,
        importance="medium",
        recent_misses=0,
        got_item_recently=False,
    )

    rng = random.Random(42)
    computed = ItemDropMath.compute_base_probability(ctx)
    result = ItemDropMath.decide_award(ctx, rng=rng)

    assert math.isclose(result["prob"], computed, rel_tol=1e-9)
    # roll must be present and between 0 and 1
    assert 0.0 <= result["roll"] <= 1.0
    # award boolean must reflect roll < prob
    expected_award = result["roll"] < result["prob"]
    assert result["award"] is expected_award


def test_drought_hard_guarantee_triggers_award():
    """
    When recent_misses >= DROUGHT_HARD_GUARANTEE, the decision should be a guaranteed award.
    """
    ctx = DecisionContext(
        user_id="u2",
        wish_id="w2",
        task_id="t2",
        task_title="Drought task",
        is_repeat=False,
        repeated_amount=0,
        importance="medium",
        recent_misses=DROUGHT_HARD_GUARANTEE,
        got_item_recently=False,
    )

    result = ItemDropMath.decide_award(ctx, rng=random.Random(1))
    assert result["award"] is True
    # drought guarantee normalizes to prob = 1.0 in the wrapper
    assert result["prob"] == pytest.approx(1.0)
    assert result["reason"] == "drought_guarantee"


def test_drought_threshold_increases_probability_over_base():
    """
    If recent_misses passes a drought threshold, compute_base_probability should be
    strictly greater than BASE_PROB (for our chosen importance/repeat combination).
    """
    # pick a misses value just above the first drought threshold to ensure multiplier applies
    first_thresh, first_mult = DROUGHT_THRESHOLDS[0]
    misses = first_thresh + 1

    ctx = DecisionContext(
        user_id="u3",
        wish_id="w3",
        task_id="t3",
        task_title="Drought increase test",
        is_repeat=False,
        repeated_amount=0,
        importance="medium",
        recent_misses=misses,
        got_item_recently=False,
    )

    base_p = BASE_PROB
    p = ItemDropMath.compute_base_probability(ctx)

    # sanity: p should be > base_p because drought multiplier should apply
    assert p > base_p
    # also ensure p is finite and within 0..1 (module clamps to MAX_EFFECTIVE_PROB)
    assert math.isfinite(p)
    assert 0.0 <= p <= 1.0
