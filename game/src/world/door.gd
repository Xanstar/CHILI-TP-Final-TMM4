class_name Door
extends Node3D
## La salida. Se ilumina a medida que Kaiser la sostiene con la mirada:
## es la única pista de que irse es una opción.

var _panel: StandardMaterial3D


func build() -> void:
	scale = Vector3.ONE * 1.6
	var frame := Shapes.material(Color(0.12, 0.1, 0.09))
	Shapes.add_mesh(self, Shapes.box(Vector3(0.15, 2.3, 0.2)), frame, Vector3(-0.7, 1.15, 0))
	Shapes.add_mesh(self, Shapes.box(Vector3(0.15, 2.3, 0.2)), frame, Vector3(0.7, 1.15, 0))
	Shapes.add_mesh(self, Shapes.box(Vector3(1.55, 0.15, 0.2)), frame, Vector3(0, 2.3, 0))

	_panel = Shapes.material(Color(0.2, 0.17, 0.12), Color(1.0, 0.8, 0.5), 0.6)
	Shapes.add_mesh(self, Shapes.box(Vector3(1.25, 2.2, 0.05)), _panel, Vector3(0, 1.1, -0.05))
	Shapes.add_light(self, Vector3(0, 1.1, 0.8), Color(1.0, 0.8, 0.5), 1.5, 5.0)


## [param urgency] va de 0 (nadie la mira) a 1 (irse).
func set_urgency(urgency: float) -> void:
	_panel.emission_energy_multiplier = 0.6 + urgency * 2.0
