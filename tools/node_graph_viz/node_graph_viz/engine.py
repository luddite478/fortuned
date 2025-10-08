from __future__ import annotations

from typing import List, Optional, Tuple
from PyQt5 import QtCore
import numpy as np

try:
	from .backend import NodeGraphBackend  # optional
except Exception:
	NodeGraphBackend = None  # type: ignore[misc,assignment]


class SequencerEngine(QtCore.QObject):
	"""Timer-driven 16-step sequencer with 16 columns.

	- Each column (step) can hold one sample on the diagonal cell
	- Playback advances left-to-right through columns
	- Each column uses its own miniaudio node
	- Supports zoom for waveform visualization
	"""

	stepAdvanced = QtCore.pyqtSignal(int)  # current step/column index (0..15)
	stateChanged = QtCore.pyqtSignal()
	columnChanged = QtCore.pyqtSignal(int)

	def __init__(self, parent: Optional[QtCore.QObject] = None) -> None:
		super().__init__(parent)
		self.current_step: int = 0
		self.tempo_bpm: float = 120.0
		self.samples: List[Optional[Tuple[np.ndarray, int]]] = [None for _ in range(16)]
		self._timer = QtCore.QTimer(self)
		self._timer.timeout.connect(self._on_tick)
		self._update_timer_interval()
		self._backend = None
		if NodeGraphBackend is not None:
			try:
				self._backend = NodeGraphBackend()
			except Exception:
				self._backend = None

	def _update_timer_interval(self) -> None:
		# 16th note duration in ms
		ms = 60000.0 / (self.tempo_bpm * 4.0)
		self._timer.setInterval(int(ms))

	def set_tempo(self, bpm: float) -> None:
		self.tempo_bpm = max(20.0, min(300.0, float(bpm)))
		self._update_timer_interval()
		self.stateChanged.emit()

	def load_sample(self, column: int, data: np.ndarray, sample_rate: int) -> None:
		if not (0 <= column < 16):
			return
		if data.ndim == 2:
			data = data.mean(axis=1)
		data = data.astype(np.float32, copy=False)
		if data.max(initial=0.0) > 1.0 or data.min(initial=0.0) < -1.0:
			peak = float(max(abs(data.max()), abs(data.min()), 1e-9))
			data = data / peak
		self.samples[column] = (data, int(sample_rate))
		self.columnChanged.emit(column)

	def start(self) -> None:
		self._timer.start()
		if self._backend is not None:
			try:
				self._backend.start()
			except Exception:
				pass
		self.stateChanged.emit()

	def stop(self) -> None:
		self._timer.stop()
		if self._backend is not None:
			try:
				self._backend.stop()
			except Exception:
				pass
		self.stateChanged.emit()

	def is_running(self) -> bool:
		return self._timer.isActive()

	def backend_load_path(self, column: int, path: str) -> None:
		if self._backend is None:
			return
		try:
			self._backend.load(column, path)
		except Exception:
			pass

	def backend_trigger(self, column: int) -> None:
		if self._backend is None:
			return
		try:
			self._backend.trigger(column)
		except Exception:
			pass

	def _on_tick(self) -> None:
		self.current_step = (self.current_step + 1) % 16
		# Trigger if sample loaded in this column
		if self.samples[self.current_step] is not None:
			self.backend_trigger(self.current_step)
		self.stepAdvanced.emit(self.current_step)
