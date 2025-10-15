from __future__ import annotations

from typing import Optional, Tuple, List
from PyQt5 import QtWidgets, QtGui, QtCore
import numpy as np
import soundfile as sf

from .engine import SequencerEngine


class GridCell(QtWidgets.QWidget):
	"""Single cell in 16x16 grid. Only diagonal cells are interactive."""
	clicked = QtCore.pyqtSignal(int, int)  # row, col

	def __init__(self, engine: SequencerEngine, row: int, col: int, parent: Optional[QtWidgets.QWidget] = None) -> None:
		super().__init__(parent)
		self.engine = engine
		self.row = row
		self.col = col
		self.is_diagonal = (row == col)
		self.setSizePolicy(QtWidgets.QSizePolicy.Fixed, QtWidgets.QSizePolicy.Fixed)
		self.engine.stepAdvanced.connect(lambda _: self.update())
		self.engine.columnChanged.connect(self._maybe_update)
		self._hover = False

	def _maybe_update(self, col: int) -> None:
		if col == self.col:
			self.update()

	def mousePressEvent(self, event: QtGui.QMouseEvent) -> None:
		if event.button() == QtCore.Qt.LeftButton and self.is_diagonal:
			self.clicked.emit(self.row, self.col)

	def enterEvent(self, _: QtCore.QEvent) -> None:
		if self.is_diagonal:
			self._hover = True
			self.update()

	def leaveEvent(self, _: QtCore.QEvent) -> None:
		self._hover = False
		self.update()

	def paintEvent(self, _: QtGui.QPaintEvent) -> None:
		p = QtGui.QPainter(self)
		p.setRenderHint(QtGui.QPainter.Antialiasing, False)
		
		w = self.width()
		h = self.height()
		
		# Background
		if self.is_diagonal:
			# Diagonal cell - can hold sample
			has_sample = self.engine.samples[self.col] is not None
			is_current_column = (self.col == self.engine.current_step)
			
			if is_current_column:
				bg = QtGui.QColor(80, 70, 40) if not has_sample else QtGui.QColor(100, 90, 50)
			else:
				bg = QtGui.QColor(35, 35, 40) if not has_sample else QtGui.QColor(45, 45, 50)
			
			if self._hover:
				bg = bg.lighter(130)
			
			p.fillRect(self.rect(), bg)
			
			# Border for diagonal cells
			p.setPen(QtGui.QPen(QtGui.QColor(70, 140, 200) if has_sample else QtGui.QColor(60, 60, 65), 1))
			p.drawRect(0, 0, w - 1, h - 1)
		else:
			# Non-diagonal cell - empty for now
			is_current_column = (self.col == self.engine.current_step)
			bg = QtGui.QColor(25, 25, 28) if not is_current_column else QtGui.QColor(35, 32, 30)
			p.fillRect(self.rect(), bg)
			p.setPen(QtGui.QPen(QtGui.QColor(40, 40, 42), 1))
			p.drawRect(0, 0, w - 1, h - 1)


class GridTable(QtWidgets.QWidget):
	"""16x16 grid with diagonal ladder pattern for samples."""
	
	def __init__(self, engine: SequencerEngine, parent: Optional[QtWidgets.QWidget] = None) -> None:
		super().__init__(parent)
		self.engine = engine
		self.cells: List[List[GridCell]] = []
		self.base_cell_size = 50
		self.current_zoom = 1.0
		
		layout = QtWidgets.QGridLayout(self)
		layout.setContentsMargins(0, 0, 0, 0)
		layout.setSpacing(1)
		
		# Create 16x16 grid
		for row in range(16):
			row_cells = []
			for col in range(16):
				cell = GridCell(engine, row, col)
				cell.clicked.connect(self._on_cell_clicked)
				cell.setFixedSize(self.base_cell_size, self.base_cell_size)
				layout.addWidget(cell, row, col)
				row_cells.append(cell)
			self.cells.append(row_cells)
		
		# Connect signals for waveform overlay updates
		self.engine.columnChanged.connect(lambda _: self.update())
		self.engine.stateChanged.connect(self.update)
		self.engine.stepAdvanced.connect(lambda _: self.update())
	
	def set_zoom(self, zoom: float) -> None:
		"""Scale the grid cells."""
		self.current_zoom = zoom
		cell_size = int(self.base_cell_size * zoom)
		for row in self.cells:
			for cell in row:
				cell.setFixedSize(cell_size, cell_size)
		self.updateGeometry()
		self.adjustSize()
		self.update()
	
	def paintEvent(self, event: QtGui.QPaintEvent) -> None:
		"""Draw time-scaled waveforms as overlay on the grid."""
		super().paintEvent(event)
		p = QtGui.QPainter(self)
		p.setRenderHint(QtGui.QPainter.Antialiasing, True)
		
		# Calculate time scale
		time_per_step = 60.0 / (self.engine.tempo_bpm * 4.0)
		cell_size = int(self.base_cell_size * self.current_zoom)
		cell_time = time_per_step  # Each column = one 16th note
		pixels_per_second = (cell_size + 1) / cell_time  # +1 for spacing
		
		# Draw waveform for each diagonal cell
		for diag_idx in range(16):
			sample_data = self.engine.samples[diag_idx]
			if sample_data is None:
				continue
			
			data, sample_rate = sample_data
			if data.size == 0:
				continue
			
			# Get position of diagonal cell
			cell = self.cells[diag_idx][diag_idx]
			cell_pos = cell.pos()
			cell_h = cell.height()
			
			# Calculate waveform width in pixels
			sample_duration = data.shape[0] / float(sample_rate)
			waveform_width = int(sample_duration * pixels_per_second)
			
			if waveform_width < 1:
				continue
			
			# Draw waveform starting from diagonal cell
			self._draw_waveform_overlay(
				p, data, 
				cell_pos.x(), cell_pos.y(),
				waveform_width, cell_h
			)
	
	def _draw_waveform_overlay(self, p: QtGui.QPainter, data: np.ndarray,
	                            x: int, y: int, w: int, h: int) -> None:
		"""Draw time-scaled waveform as overlay."""
		if w < 2 or h < 2:
			return
		
		# Downsample to pixel width
		bucket_size = max(1, int(np.ceil(data.shape[0] / w)))
		trim = (data.shape[0] // bucket_size) * bucket_size
		if trim < bucket_size:
			return
		
		chunk = data[:trim].reshape(-1, bucket_size)
		mins = chunk.min(axis=1)
		maxs = chunk.max(axis=1)
		
		scale = 0.8 * (h / 2.0)
		mid = y + h / 2.0
		
		# Draw with thick semi-transparent pen
		p.setPen(QtGui.QPen(QtGui.QColor(100, 180, 240, 180), 1.5))
		for i in range(min(len(mins), w)):
			px = x + i
			y1 = int(mid - mins[i] * scale)
			y2 = int(mid - maxs[i] * scale)
			if y1 > y2:
				y1, y2 = y2, y1
			p.drawLine(px, y1, px, y2)
	
	def _on_cell_clicked(self, row: int, col: int) -> None:
		"""Load sample when diagonal cell is clicked."""
		if row == col:
			self._load_sample(col)
	
	def _load_sample(self, col: int) -> None:
		path, _ = QtWidgets.QFileDialog.getOpenFileName(
			self, 
			f"Choose sample for position {col + 1}", 
			"", 
			"Audio Files (*.wav *.flac *.ogg *.aiff *.aif *.mp3)"
		)
		if not path:
			return
		
		try:
			data, sr = sf.read(path, always_2d=False)
			if isinstance(data, np.ndarray):
				self.engine.load_sample(col, data, int(sr))
				self.engine.backend_load_path(col, path)
		except Exception as exc:
			QtWidgets.QMessageBox.critical(self, "Load Error", f"Failed to load sample:\n{exc}")


class MainWindow(QtWidgets.QMainWindow):
	def __init__(self) -> None:
		super().__init__()
		self.setWindowTitle("Node Graph Viz - 16x16 Grid Sequencer")
		self.engine = SequencerEngine(self)

		central = QtWidgets.QWidget(self)
		self.setCentralWidget(central)
		main_layout = QtWidgets.QVBoxLayout(central)
		main_layout.setContentsMargins(8, 8, 8, 8)
		main_layout.setSpacing(8)

		# Top: global controls
		controls = self._build_global_controls()
		main_layout.addWidget(controls)

		# Main: 16x16 Grid with scroll
		scroll_area = QtWidgets.QScrollArea()
		scroll_area.setWidgetResizable(False)
		scroll_area.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAsNeeded)
		scroll_area.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAsNeeded)
		
		self.grid = GridTable(self.engine)
		scroll_area.setWidget(self.grid)
		main_layout.addWidget(scroll_area, 1)

	def _build_global_controls(self) -> QtWidgets.QWidget:
		w = QtWidgets.QWidget()
		l = QtWidgets.QHBoxLayout(w)
		l.setContentsMargins(0, 0, 0, 0)
		l.setSpacing(12)

		self.tempo_spin = QtWidgets.QDoubleSpinBox()
		self.tempo_spin.setRange(20.0, 300.0)
		self.tempo_spin.setDecimals(1)
		self.tempo_spin.setValue(120.0)
		self.tempo_spin.setSuffix(" BPM")
		self.tempo_spin.valueChanged.connect(self.engine.set_tempo)
		l.addWidget(QtWidgets.QLabel("Tempo:"))
		l.addWidget(self.tempo_spin)

		self.start_btn = QtWidgets.QPushButton("Start")
		self.start_btn.clicked.connect(self._on_start_stop)
		l.addWidget(self.start_btn)

		# Horizontal zoom control
		l.addWidget(QtWidgets.QLabel("Zoom:"))
		self.zoom_slider = QtWidgets.QSlider(QtCore.Qt.Horizontal)
		self.zoom_slider.setRange(5, 50)  # 0.5x to 5.0x
		self.zoom_slider.setValue(10)  # 1.0x default
		self.zoom_slider.setFixedWidth(150)
		self.zoom_slider.valueChanged.connect(self._on_zoom_changed)
		l.addWidget(self.zoom_slider)
		self.zoom_label = QtWidgets.QLabel("1.0x")
		self.zoom_label.setFixedWidth(50)
		l.addWidget(self.zoom_label)

		l.addStretch(1)
		return w

	def _on_start_stop(self) -> None:
		if self.engine.is_running():
			self.engine.stop()
			self.start_btn.setText("Start")
		else:
			self.engine.start()
			self.start_btn.setText("Stop")

	def _on_zoom_changed(self, value: int) -> None:
		zoom = value / 10.0  # Convert slider value to zoom factor
		self.grid.set_zoom(zoom)
		self.zoom_label.setText(f"{zoom:.1f}x")
