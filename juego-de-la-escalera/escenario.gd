extends Node3D
## Duelo de reacción sobre una escalera mecánica que baja hacia un foso.
## Cada jugador tiene una flecha objetivo que NO cambia por tiempo: se queda
## igual hasta que se pulsa la dirección correcta. Acertar sube un poco por
## la escalera; equivocarse te hace retroceder. La escalera acelera sin parar
## hasta que alguien cae al foso. Cuando queda un solo jugador, la escalera frena.
##
## Jugador 1 (azul) -> W/A/S/D según la flecha mostrada.
## Jugador 2 (rojo)  -> flechas del teclado.

## ganador: 1 o 2. 0 significa empate (cayeron en el mismo instante).
signal juego_terminado(ganador: int, duracion: float)
signal tiempo_actualizado(segundos: float)

@onready var escalera: Node3D = $Escalera
@onready var nodo_escalones: Node3D = $Escalera/Escalones
@onready var jugador1: Node3D = $Jugador1
@onready var jugador2: Node3D = $Jugador2
@onready var flecha1: Label3D = $Jugador1/Flecha
@onready var flecha2: Label3D = $Jugador2/Flecha
@onready var cuenta_regresiva: Label3D = $CuentaRegresiva
@onready var camara: Camera3D = $Camara

enum Direccion { ARRIBA, ABAJO, IZQUIERDA, DERECHA }

## NORMAL: la cámara está en el encuadre de la escena.
## DRAMATICA: sigue de cerca al jugador que cae, con zoom y otro ángulo.
## REGRESANDO: vuelve suavemente al encuadre normal.
enum EstadoCamara { NORMAL, DRAMATICA, REGRESANDO }

const NUM_JUGADORES: int = 2

const FLECHAS := {
	Direccion.ARRIBA: "↑",
	Direccion.ABAJO: "↓",
	Direccion.IZQUIERDA: "←",
	Direccion.DERECHA: "→",
}

## Un diccionario por jugador: tecla física -> dirección.
const TECLAS_JUGADORES := [
	{
		KEY_W: Direccion.ARRIBA,
		KEY_S: Direccion.ABAJO,
		KEY_A: Direccion.IZQUIERDA,
		KEY_D: Direccion.DERECHA,
	},
	{
		KEY_UP: Direccion.ARRIBA,
		KEY_DOWN: Direccion.ABAJO,
		KEY_LEFT: Direccion.IZQUIERDA,
		KEY_RIGHT: Direccion.DERECHA,
	},
]

# --- Geometría (debe coincidir con el nodo Escalera de la escena) ---
const LARGO_ESCALERA: float = 11.0    # metros a lo largo de la pendiente
const ANCHO_ESCALERA: float = 5.6
const NUM_ESCALONES: int = 22         # par, para que los colores alternen bien al reciclar
const ESPACIO_ESCALON: float = LARGO_ESCALERA / NUM_ESCALONES
const ALTURA_ESCALON: float = 0.14
const CARRILES: Array[float] = [-1.4, 1.4] # posición Z de cada jugador sobre la escalera
const COLOR_ESCALON_A := Color(0.62, 0.62, 0.68, 1)
const COLOR_ESCALON_B := Color(0.45, 0.45, 0.5, 1)

# --- Caída al foso ---
const DESTINO_CAIDA_X: float = -6.2
const DESTINO_CAIDA_Y: float = -4.4
const DURACION_CAIDA: float = 0.9

# --- Colores de las flechas ---
const COLORES_FLECHA: Array[Color] = [Color(0.65, 0.8, 1.0, 1), Color(1.0, 0.7, 0.7, 1)]
const COLOR_ERROR := Color(1.0, 0.1, 0.1, 1)
const DURACION_DESTELLO_ERROR: float = 0.25

# --- Cuenta regresiva antes de empezar/reiniciar ---
const DURACION_CUENTA_REGRESIVA_PASO: float = 1.0 # segundos reales por número

# --- Balance (el progreso va de 0 = caés al foso a 1 = arriba de todo) ---
@export_group("Balance")
@export var progreso_inicial: float = 0.6
@export var incremento_acierto: float = 0.035
@export var penalizacion_error: float = 0.025
## Velocidad de bajada al empezar, en fracción de escalera por segundo.
@export var velocidad_inicial: float = 0.03
## Cuánto aumenta la velocidad de bajada por cada segundo transcurrido.
@export var aceleracion: float = 0.0025
@export var velocidad_maxima: float = 0.8
## Cuánto baja la velocidad por segundo cuando la escalera frena.
@export var frenado: float = 0.3

@export_group("Cámara dramática")
@export var camara_dramatica_activa: bool = true
## Campo de visión al seguir la caída (menor = más zoom). El normal se toma de la cámara de la escena.
@export var fov_dramatico: float = 30.0
## Posición de la cámara relativa al jugador que cae: X derecha, Y arriba, Z hacia la pantalla.
@export var offset_camara_dramatica: Vector3 = Vector3(3.2, 1.6, 5.0)
## Altura sobre los pies del jugador hacia donde mira la cámara.
@export var altura_mira: float = 0.6
## Qué tan rápido se mueve la cámara hacia su destino (mayor = más brusco).
@export var velocidad_camara: float = 4.5
## Si es true, la cámara vuelve al encuadre normal después de la caída.
@export var volver_a_vista_normal: bool = true
## Segundos que se queda mirando la caída antes de volver al encuadre normal.
@export var retraso_regreso: float = 2.2

var progreso: Array[float] = [0.0, 0.0]
var objetivo: Array[int] = [Direccion.ARRIBA, Direccion.ARRIBA]
var vivo: Array[bool] = [true, true]
var jugadores: Array[Node3D] = []
var flechas: Array[Label3D] = []
var destellos: Array[Tween] = [null, null]
var caidas: Array[Tween] = [null, null]

var escalones: Array[CSGBox3D] = []
var desplazamiento: float = 0.0 # metros recorridos por los escalones hacia abajo
var velocidad: float = 0.0      # fracción de escalera por segundo
var tiempo_partida: float = 0.0
var jugando: bool = false
var id_ronda_actual: int = 0

var estado_camara: EstadoCamara = EstadoCamara.NORMAL
var transform_camara_normal: Transform3D
var fov_camara_normal: float = 45.0


func _ready() -> void:
	jugadores = [jugador1, jugador2]
	flechas = [flecha1, flecha2]
	transform_camara_normal = camara.global_transform
	fov_camara_normal = camara.fov
	_crear_escalones()
	iniciar()


## Genera los escalones que se reciclan: cada uno baja por la pendiente y al
## llegar abajo reaparece arriba, así se ve la escalera en movimiento.
func _crear_escalones() -> void:
	var material_a := StandardMaterial3D.new()
	material_a.albedo_color = COLOR_ESCALON_A
	var material_b := StandardMaterial3D.new()
	material_b.albedo_color = COLOR_ESCALON_B

	for i in NUM_ESCALONES:
		var escalon := CSGBox3D.new()
		escalon.size = Vector3(ESPACIO_ESCALON * 0.92, ALTURA_ESCALON, ANCHO_ESCALERA)
		escalon.material = material_a if i % 2 == 0 else material_b
		nodo_escalones.add_child(escalon)
		escalones.append(escalon)


## Arranca (o reinicia) el duelo desde cero: resetea todo, corre la cuenta
## regresiva con las flechas ocultas, y recién al final habilita el juego.
func iniciar() -> void:
	id_ronda_actual += 1
	var mi_id: int = id_ronda_actual

	jugando = false
	velocidad = 0.0
	tiempo_partida = 0.0
	desplazamiento = 0.0
	estado_camara = EstadoCamara.REGRESANDO

	for i in NUM_JUGADORES:
		if destellos[i]:
			destellos[i].kill()
		if caidas[i]:
			caidas[i].kill()
		progreso[i] = progreso_inicial
		vivo[i] = true
		jugadores[i].rotation_degrees = Vector3.ZERO
		flechas[i].modulate = COLORES_FLECHA[i]
		flechas[i].visible = false

	_mover_escalones()
	_actualizar_visuales()
	tiempo_actualizado.emit(0.0)

	await _correr_cuenta_regresiva(mi_id)
	if mi_id != id_ronda_actual:
		return # se pidió otro reinicio mientras contábamos; esta ronda quedó obsoleta

	for i in NUM_JUGADORES:
		flechas[i].visible = true
		_nuevo_objetivo(i)
	jugando = true


## "3... 2... 1..." con número grande en pantalla. Revisa mi_id después de
## cada espera por si se pidió otro reinicio mientras tanto (R repetido).
func _correr_cuenta_regresiva(mi_id: int) -> void:
	cuenta_regresiva.visible = true
	for numero in [3, 2, 1]:
		cuenta_regresiva.text = str(numero)
		await get_tree().create_timer(DURACION_CUENTA_REGRESIVA_PASO).timeout
		if mi_id != id_ronda_actual:
			return

	cuenta_regresiva.visible = false


func _process(delta: float) -> void:
	if jugando:
		tiempo_partida += delta
		velocidad = minf(velocidad_inicial + aceleracion * tiempo_partida, velocidad_maxima)

		for i in NUM_JUGADORES:
			if vivo[i]:
				progreso[i] -= velocidad * delta

		_actualizar_visuales()
		_revisar_caidas()
		tiempo_actualizado.emit(tiempo_partida)
	elif velocidad > 0.0:
		velocidad = move_toward(velocidad, 0.0, frenado * delta)

	desplazamiento += velocidad * LARGO_ESCALERA * delta
	_mover_escalones()
	_actualizar_camara(delta)


func _input(evento: InputEvent) -> void:
	var tecla := evento as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return

	var pulsacion: Vector2i = _traducir_tecla(tecla.physical_keycode)
	if pulsacion.x < 0:
		return

	_registrar_pulsacion(pulsacion.x, pulsacion.y)


## Traduce una tecla física a (índice de jugador, dirección). Devuelve
## (-1, -1) si la tecla no pertenece a ningún jugador. Es el único punto que
## conoce el teclado: para migrar al micro:bit basta con llamar a
## _registrar_pulsacion desde la nueva fuente de entrada.
func _traducir_tecla(codigo: Key) -> Vector2i:
	for i in NUM_JUGADORES:
		if TECLAS_JUGADORES[i].has(codigo):
			return Vector2i(i, TECLAS_JUGADORES[i][codigo])
	return Vector2i(-1, -1)


## indice: 0 = Jugador 1, 1 = Jugador 2.
func _registrar_pulsacion(indice: int, direccion: int) -> void:
	if not jugando or not vivo[indice]:
		return

	if direccion == objetivo[indice]:
		progreso[indice] = minf(progreso[indice] + incremento_acierto, 1.0)
		_nuevo_objetivo(indice)
	else:
		progreso[indice] -= penalizacion_error
		_destello_error(indice)

	_actualizar_visuales()
	_revisar_caidas()


func _nuevo_objetivo(indice: int) -> void:
	if destellos[indice]:
		destellos[indice].kill()
	objetivo[indice] = _direccion_aleatoria_distinta(objetivo[indice])
	flechas[indice].text = FLECHAS[objetivo[indice]]
	flechas[indice].modulate = COLORES_FLECHA[indice]


## Nueva dirección al azar, evitando repetir la anterior (se siente más vivo).
func _direccion_aleatoria_distinta(anterior: int) -> int:
	var opciones := Direccion.values()
	var nueva: int = opciones[randi() % opciones.size()]
	while nueva == anterior:
		nueva = opciones[randi() % opciones.size()]
	return nueva


## La flecha se tiñe de rojo un instante: como no cambia al fallar, esto es
## lo que avisa que la pulsación fue incorrecta.
func _destello_error(indice: int) -> void:
	if destellos[indice]:
		destellos[indice].kill()
	flechas[indice].modulate = COLOR_ERROR
	var tween := create_tween()
	tween.tween_property(flechas[indice], "modulate", COLORES_FLECHA[indice], DURACION_DESTELLO_ERROR)
	destellos[indice] = tween


## Coloca a cada jugador vivo sobre la escalera según su progreso.
func _actualizar_visuales() -> void:
	for i in NUM_JUGADORES:
		if vivo[i]:
			var distancia: float = clampf(progreso[i], 0.0, 1.0) * LARGO_ESCALERA
			jugadores[i].global_position = escalera.to_global(
				Vector3(distancia, ALTURA_ESCALON * 0.5, CARRILES[i])
			)


## Posiciona los escalones según lo que ya bajó la escalera; al llegar al
## final de la pendiente reaparecen arriba.
func _mover_escalones() -> void:
	for i in escalones.size():
		var distancia: float = fposmod(i * ESPACIO_ESCALON - desplazamiento, LARGO_ESCALERA)
		escalones[i].position = Vector3(distancia, 0.0, 0.0)


func _revisar_caidas() -> void:
	if not jugando:
		return

	var hubo_caida: bool = false
	for i in NUM_JUGADORES:
		if vivo[i] and progreso[i] <= 0.0:
			_caer(i)
			hubo_caida = true

	if not hubo_caida:
		return

	var sobrevivientes: Array[int] = []
	for i in NUM_JUGADORES:
		if vivo[i]:
			sobrevivientes.append(i)

	if sobrevivientes.size() == 1:
		_terminar(sobrevivientes[0] + 1)
	elif sobrevivientes.is_empty():
		_terminar(0)


func _caer(indice: int) -> void:
	vivo[indice] = false
	flechas[indice].visible = false
	if destellos[indice]:
		destellos[indice].kill()

	var jugador: Node3D = jugadores[indice]
	_activar_camara_dramatica()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(jugador, "global_position:x", DESTINO_CAIDA_X, DURACION_CAIDA)
	tween.tween_property(jugador, "global_position:y", DESTINO_CAIDA_Y, DURACION_CAIDA) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(jugador, "rotation_degrees:z", 80.0, DURACION_CAIDA)
	caidas[indice] = tween


## Con un solo jugador en pie el juego se detiene: la escalera frena sola en
## _process porque jugando pasa a false y la velocidad decae hasta cero.
func _terminar(ganador: int) -> void:
	jugando = false
	for i in NUM_JUGADORES:
		flechas[i].visible = false
	juego_terminado.emit(ganador, tiempo_partida)

	if camara_dramatica_activa and volver_a_vista_normal:
		_regresar_camara_tras_espera(id_ronda_actual)


## La cámara deja el encuadre normal y pasa a seguir la caída de cerca.
func _activar_camara_dramatica() -> void:
	if camara_dramatica_activa:
		estado_camara = EstadoCamara.DRAMATICA


## Deja la cámara mirando la caída un rato y luego la manda de vuelta al
## encuadre normal. Si mientras tanto se reinició la ronda, no hace nada.
func _regresar_camara_tras_espera(mi_id: int) -> void:
	await get_tree().create_timer(retraso_regreso).timeout
	if mi_id == id_ronda_actual and estado_camara == EstadoCamara.DRAMATICA:
		estado_camara = EstadoCamara.REGRESANDO


## Punto que mira la cámara dramática: el jugador caído, o el punto medio
## entre los dos si cayeron a la vez.
func _punto_de_interes() -> Vector3:
	var suma := Vector3.ZERO
	var cantidad: int = 0
	for i in NUM_JUGADORES:
		if not vivo[i]:
			suma += jugadores[i].global_position
			cantidad += 1

	if cantidad == 0:
		return jugadores[0].global_position + Vector3(0.0, altura_mira, 0.0)
	return suma / cantidad + Vector3(0.0, altura_mira, 0.0)


## Mueve posición, rotación y FOV de la cámara hacia su destino con un
## suavizado que no depende de los FPS.
func _actualizar_camara(delta: float) -> void:
	if estado_camara == EstadoCamara.NORMAL:
		return

	var peso: float = 1.0 - exp(-velocidad_camara * delta)
	var destino: Transform3D
	var fov_destino: float

	if estado_camara == EstadoCamara.DRAMATICA:
		var mira: Vector3 = _punto_de_interes()
		destino = Transform3D(Basis.IDENTITY, mira + offset_camara_dramatica).looking_at(mira, Vector3.UP)
		fov_destino = fov_dramatico
	else:
		destino = transform_camara_normal
		fov_destino = fov_camara_normal

	camara.global_transform = camara.global_transform.interpolate_with(destino, peso)
	camara.fov = lerpf(camara.fov, fov_destino, peso)

	if estado_camara == EstadoCamara.REGRESANDO \
			and camara.global_position.distance_to(destino.origin) < 0.02 \
			and absf(camara.fov - fov_destino) < 0.05:
		camara.global_transform = transform_camara_normal
		camara.fov = fov_camara_normal
		estado_camara = EstadoCamara.NORMAL


## Llamado desde Principal.gd al presionar "R".
func reiniciar() -> void:
	iniciar()
