class_name Player
extends CharacterBody2D

signal died
signal attacked

enum State { IDLE, RUN, JUMP, FALL, DASH, ATTACK, HURT, DEAD }

const SPEED: float = 180.0
const ACCELERATION: float = 1400.0
const FRICTION: float = 1600.0
const JUMP_VELOCITY: float = -340.0
const DASH_SPEED: float = 420.0
const DASH_TIME: float = 0.18
const DASH_COST: float = 35.0
const COYOTE_TIME: float = 0.1
const JUMP_BUFFER_TIME: float = 0.12

@export var gravity_scale: float = 1.0
@export var knockback_resistance: float = 0.5
@export var attack_damage: int = 1

var state: State = State.IDLE
var facing: int = 1
var can_double_jump: bool = false
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _dash_timer: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var health: HealthComponent = $HealthComponent
@onready var energy: EnergyComponent = $EnergyComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var attack_hitbox: Hitbox = %AttackHitbox
@onready var attack_cooldown: Timer = $AttackCooldown
@onready var camera: PlayerCamera = $PlayerCamera
@onready var jump_sound: AudioStreamPlayer2D = $JumpSound


func _ready() -> void:
	add_to_group("player")
	health.died.connect(_on_health_died)
	health.damaged.connect(_on_health_damaged)
	hurtbox.hit_received.connect(_on_hurtbox_hit_received)
	attack_hitbox.monitoring = false
	if GameState.has_upgrade(&"max_health"):
		health.set_max_health(health.max_health + 1)
	if GameState.has_upgrade(&"attack_damage"):
		attack_damage += 1
	attack_hitbox.damage = attack_damage
	if GameState.has_checkpoint:
		global_position = GameState.last_checkpoint


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_update_timers(delta)
	match state:
		State.DASH:
			_process_dash(delta)
		State.HURT:
			_apply_gravity(delta)
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		_:
			_apply_gravity(delta)
			_process_movement(delta)
			_process_jump()
			_process_actions()
	move_and_slide()
	_update_state()
	_update_animation()


func _update_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = COYOTE_TIME
		can_double_jump = GameState.has_upgrade(&"double_jump")
	else:
		_coyote_timer -= delta
	_jump_buffer_timer -= delta
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = JUMP_BUFFER_TIME


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * gravity_scale * delta


func _process_movement(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
		velocity.x = move_toward(velocity.x, direction * SPEED, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
	if Input.is_action_pressed("move_down") and is_on_floor():
		position.y += 1.0


func _process_jump() -> void:
	if _jump_buffer_timer <= 0.0:
		if Input.is_action_just_released("jump") and velocity.y < 0.0:
			velocity.y *= 0.5
		return
	if _coyote_timer > 0.0:
		_jump()
	elif can_double_jump:
		can_double_jump = false
		_jump()


func _jump() -> void:
	velocity.y = JUMP_VELOCITY
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	jump_sound.play()


func _process_actions() -> void:
	if Input.is_action_just_pressed("attack") and attack_cooldown.is_stopped():
		_attack()
	elif Input.is_action_just_pressed("dash") and GameState.has_upgrade(&"dash"):
		_start_dash()


func _attack() -> void:
	state = State.ATTACK
	attack_cooldown.start()
	attack_hitbox.scale.x = facing
	attack_hitbox.monitoring = true
	animation_player.play("attack")
	AudioService.play_sfx(&"swing")
	attacked.emit()
	await animation_player.animation_finished
	attack_hitbox.monitoring = false
	if state == State.ATTACK:
		state = State.IDLE


func _start_dash() -> void:
	if not energy.spend(DASH_COST):
		return
	state = State.DASH
	_dash_timer = DASH_TIME
	velocity = Vector2(facing * DASH_SPEED, 0.0)
	hurtbox.set_deferred("monitoring", false)
	AudioService.play_sfx(&"dash")


func _process_dash(delta: float) -> void:
	_dash_timer -= delta
	if _dash_timer <= 0.0:
		state = State.FALL
		velocity.x = facing * SPEED
		hurtbox.set_deferred("monitoring", true)


func _update_state() -> void:
	if state in [State.DASH, State.ATTACK, State.HURT, State.DEAD]:
		return
	if not is_on_floor():
		state = State.JUMP if velocity.y < 0.0 else State.FALL
	elif absf(velocity.x) > 10.0:
		state = State.RUN
	else:
		state = State.IDLE


func _update_animation() -> void:
	sprite.flip_h = facing < 0
	match state:
		State.IDLE:
			sprite.play("idle")
		State.RUN:
			sprite.play("run")
		State.JUMP:
			sprite.play("jump")
		State.FALL:
			sprite.play("fall")
		State.DASH:
			sprite.play("dash")


func _on_hurtbox_hit_received(hitbox: Hitbox) -> void:
	if state == State.DEAD:
		return
	state = State.HURT
	velocity = hitbox.get_knockback_from(global_position) * knockback_resistance
	velocity.y = -150.0
	camera.shake(6.0, 0.2)
	await get_tree().create_timer(0.3).timeout
	if state == State.HURT:
		state = State.IDLE


func _on_health_damaged(amount: int) -> void:
	EventBus.player_damaged.emit(amount, health.current_health)
	AudioService.play_sfx(&"hurt")
	var tween := create_tween().set_loops(4)
	tween.tween_property(sprite, "modulate:a", 0.2, 0.05)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.05)


func _on_health_died() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	collision_shape.set_deferred("disabled", true)
	hurtbox.set_deferred("monitoring", false)
	sprite.play("death")
	AudioService.play_sfx(&"death")
	died.emit()
	EventBus.player_died.emit()
