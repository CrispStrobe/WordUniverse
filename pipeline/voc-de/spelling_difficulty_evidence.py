"""Explicit evidence for the existing 0–3 spelling-difficulty field.

The numeric enum remains compatible with existing readers. A compatibility
default of zero is not measured ease. These helpers label evidence; callers
retain their existing thresholds and item-selection policies.
"""

from __future__ import annotations

import math


def unknown_spelling_difficulty(compatibility_value: int = 0) -> dict:
    if type(compatibility_value) is not int or not 0 <= compatibility_value <= 3:
        raise ValueError("spellingDifficulty compatibility value must be an integer from 0 to 3")
    return {
        "spellingDifficulty": compatibility_value,
        "spellingDifficultySource": "unknown",
        "spellingDifficultyEvidence": {
            "status": "unknown",
            "source": None,
            "reason": "Compatibility default; no measured spelling evidence.",
            "calibrated": False,
        },
    }


def litkey_spelling_difficulty(
    error_rate: float,
    difficulty: int,
    *,
    sample_size: int | None = None,
    error_tokens: int | None = None,
    aggregation: str = "target",
) -> dict:
    """Attach observed LiTKey provenance without recalculating the score.

    Missing sample size remains null, rather than an invented denominator.
    Corpus evidence does not imply calibration for a child or for KOMPASS.
    """
    if (isinstance(error_rate, bool) or not isinstance(error_rate, (int, float))
            or not math.isfinite(error_rate) or not 0 <= error_rate <= 1):
        raise ValueError("LiTKey error rate must be a finite number from 0 to 1")
    if type(difficulty) is not int or not 0 <= difficulty <= 3:
        raise ValueError("spellingDifficulty must be an integer from 0 to 3")
    if sample_size is not None and (type(sample_size) is not int or sample_size <= 0):
        raise ValueError("LiTKey sample size must be a positive integer or unknown")
    if error_tokens is not None:
        if type(error_tokens) is not int or error_tokens < 0:
            raise ValueError("LiTKey error tokens must be a nonnegative integer or unknown")
        if sample_size is not None and error_tokens > sample_size:
            raise ValueError("LiTKey error tokens exceed sample size")
    if aggregation not in {"target", "lemma"}:
        raise ValueError("Unsupported LiTKey aggregation unit")
    return {
        "spellingDifficulty": difficulty,
        "spellingDifficultySource": "litkey",
        "spellingDifficultyEvidence": {
            "status": "corpus-derived",
            "source": "LiTKey",
            "errorRate": error_rate,
            "sampleSize": sample_size,
            "errorTokens": error_tokens,
            "aggregation": aggregation,
            "calibrated": False,
        },
    }
