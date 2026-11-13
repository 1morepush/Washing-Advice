"""Choosing between removers, and falling back when the learned one cannot run.

A cutout is a nicety. It must never be the reason a photograph is refused
because a model file is missing or a native library will not load, so the
learned remover is always backed by the classical one.

Two different things trigger the fallback, and they are logged differently:

* The learned remover is *unavailable* (no model, no onnxruntime, inference
  raised). That is an operator's problem, logged once per distinct reason so a
  broken deployment is visible without a line per request.
* The learned remover *ran* but its answer is implausible (empty, nearly the
  whole frame, a scrap). That is a property of the photograph, so the classical
  remover gets a go and the more plausible of the two is returned.
"""

from __future__ import annotations

import logging

from app.services.images.cutout import BackgroundRemover, Cutout, CutoutError

logger = logging.getLogger(__name__)


class FallbackRemover:
    """Tries `primary`, and `fallback` when it cannot run or is not convincing."""

    def __init__(self, primary: BackgroundRemover, fallback: BackgroundRemover) -> None:
        self._primary = primary
        self._fallback = fallback
        self._reported: set[str] = set()

    def remove(self, image_bytes: bytes) -> Cutout:
        first: Cutout | None = None
        first_error: CutoutError | None = None
        try:
            first = self._primary.remove(image_bytes)
        except CutoutError as error:
            first_error = error
        except Exception as error:
            # Deliberately broad: whatever the learned remover died of, the
            # photograph is still perfectly cuttable by the classical one.
            self._report_once(str(error))

        if first is not None and first.is_plausible:
            return first

        try:
            second = self._fallback.remove(image_bytes)
        except CutoutError:
            if first is not None:
                return first
            if first_error is not None:
                raise first_error from None
            raise
        if first is None or second.is_plausible:
            return second
        return _less_implausible(first, second)

    def _report_once(self, reason: str) -> None:
        if reason in self._reported:
            return
        self._reported.add(reason)
        logger.warning("learned cutout unavailable, using the classical remover: %s", reason)


def _less_implausible(a: Cutout, b: Cutout) -> Cutout:
    """Of two results that are both refused, the one nearer the plausible range."""

    def miss(cutout: Cutout) -> float:
        if cutout.coverage < 0.04:
            return 0.04 - cutout.coverage
        return max(0.0, cutout.coverage - 0.92)

    return a if miss(a) <= miss(b) else b
