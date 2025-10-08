from PyQt5 import QtWidgets, QtCore
from .ui import MainWindow


def main() -> None:
	QtWidgets.QApplication.setAttribute(QtCore.Qt.AA_EnableHighDpiScaling, True)
	QtWidgets.QApplication.setAttribute(QtCore.Qt.AA_UseHighDpiPixmaps, True)
	app = QtWidgets.QApplication([])
	win = MainWindow()
	win.resize(1200, 700)
	win.show()
	app.exec_()


if __name__ == "__main__":
	main()
