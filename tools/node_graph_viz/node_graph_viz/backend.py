from __future__ import annotations

import ctypes
import os
import sys
from typing import Optional


class NodeGraphBackend:
	"""ctypes wrapper around native nodegraph backend.

	Looks for libnodegraph in common build locations or NODEGRAPH_LIB env var.
	"""

	def __init__(self, lib_path: Optional[str] = None) -> None:
		self._lib = None
		self._load_library(lib_path)
		self._setup_prototypes()
		ret = self._lib.ng_init()
		if ret != 0:
			raise RuntimeError(f"ng_init failed: {ret}")
		self._started = False

	def _load_library(self, lib_path: Optional[str]) -> None:
		candidate_paths = []
		if lib_path:
			candidate_paths.append(lib_path)
		env = os.getenv("NODEGRAPH_LIB")
		if env:
			candidate_paths.append(env)
		# Default macOS build location
		root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
		native_dir = os.path.join(root, "native")
		candidate_paths.append(os.path.join(native_dir, "build", "libnodegraph.dylib"))
		candidate_paths.append(os.path.join(native_dir, "libnodegraph.dylib"))
		# Name-only fallback (on PATH / LD paths)
		candidate_paths.append("libnodegraph.dylib")
		candidate_paths.append("nodegraph.dylib")

		last_err = None
		for p in candidate_paths:
			try:
				self._lib = ctypes.CDLL(p)
				return
			except OSError as e:
				last_err = e
		raise OSError(f"Failed to load nodegraph library. Tried: {candidate_paths}. Last error: {last_err}")

	def _setup_prototypes(self) -> None:
		lib = self._lib
		lib.ng_init.restype = ctypes.c_int
		lib.ng_start.restype = ctypes.c_int
		lib.ng_stop.restype = None
		lib.ng_shutdown.restype = None
		lib.ng_load.argtypes = [ctypes.c_int, ctypes.c_char_p]
		lib.ng_load.restype = ctypes.c_int
		lib.ng_trigger.argtypes = [ctypes.c_int]
		lib.ng_trigger.restype = ctypes.c_int

	def start(self) -> None:
		if not self._started:
			ret = self._lib.ng_start()
			if ret != 0:
				raise RuntimeError(f"ng_start failed: {ret}")
			self._started = True

	def stop(self) -> None:
		if self._started:
			self._lib.ng_stop()
			self._started = False

	def shutdown(self) -> None:
		try:
			self.stop()
		finally:
			self._lib.ng_shutdown()

	def load(self, slot: int, path: str) -> None:
		ret = self._lib.ng_load(int(slot), path.encode("utf-8"))
		if ret != 0:
			raise RuntimeError(f"ng_load failed for slot {slot}: {ret}")

	def trigger(self, slot: int) -> None:
		ret = self._lib.ng_trigger(int(slot))
		if ret != 0:
			raise RuntimeError(f"ng_trigger failed for slot {slot}: {ret}")

	def __del__(self) -> None:
		# Avoid noisy exceptions on interpreter shutdown
		try:
			if self._lib is not None:
				self.shutdown()
		except Exception:
			pass

