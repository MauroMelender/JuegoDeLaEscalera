extends Node

@onready var escenario: Node3D = $Escenario
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	escenario.juego_terminado.connect(_al_terminar)
	escenario.tiempo_actualizado.connect(hud.actualizar_tiempo)


func _al_terminar(ganador: int, duracion: float) -> void:
	hud.mostrar_resultado(ganador, duracion)


func _input(evento: InputEvent) -> void:
	if evento is InputEventKey and evento.pressed and not evento.echo and evento.physical_keycode == KEY_R:
		escenario.reiniciar()
		hud.reiniciar()
