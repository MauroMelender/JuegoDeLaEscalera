extends CanvasLayer

@onready var etiqueta_estado: Label = $Estado
@onready var etiqueta_tiempo: Label = $Tiempo

const TEXTO_INICIAL := "Jugador 1 (W A S D)  vs  Jugador 2 (Flechas) — ¡acierten la flecha para subir por la escalera y no caer al foso!"


func _ready() -> void:
	etiqueta_estado.text = TEXTO_INICIAL
	actualizar_tiempo(0.0)


func actualizar_tiempo(segundos: float) -> void:
	etiqueta_tiempo.text = "%.1f s" % segundos


func mostrar_resultado(ganador: int, duracion: float) -> void:
	if ganador == 0:
		etiqueta_estado.text = "¡Empate! Cayeron a la vez tras %.1f s. Presioná R para revancha" % duracion
	else:
		etiqueta_estado.text = "¡Jugador %d gana! Resistió %.1f s. Presioná R para revancha" % [ganador, duracion]


func reiniciar() -> void:
	etiqueta_estado.text = TEXTO_INICIAL
	actualizar_tiempo(0.0)
