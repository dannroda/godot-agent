extends Control

const CARD_SCENE: PackedScene = preload("res://tests/completion_eval/project/ui/upgrade_card.tscn")

@export var upgrades: Array[UpgradeData] = []

@onready var coin_label: Label = %CoinLabel
@onready var card_container: HBoxContainer = %CardContainer
@onready var continue_button: Button = %ContinueButton


func _ready() -> void:
	GameState.coins_changed.connect(_on_coins_changed)
	continue_button.pressed.connect(_on_continue_button_pressed)
	coin_label.text = str(GameState.coins)
	_build_cards()
	continue_button.grab_focus()


func _build_cards() -> void:
	for upgrade in upgrades:
		var card: UpgradeCard = CARD_SCENE.instantiate()
		card_container.add_child(card)
		card.setup(upgrade)
		card.purchase_requested.connect(_on_card_purchase_requested)
	_refresh_cards()


func _refresh_cards() -> void:
	for card: UpgradeCard in card_container.get_children():
		card.refresh(GameState.coins, GameState.has_upgrade(card.upgrade.id))


func _on_card_purchase_requested(upgrade: UpgradeData) -> void:
	if GameState.unlock_upgrade(upgrade.id, upgrade.cost):
		AudioService.play_sfx(&"purchase")
		SaveService.save_game()
	else:
		AudioService.play_sfx(&"error")
	_refresh_cards()


func _on_coins_changed(coins: int) -> void:
	coin_label.text = str(coins)


func _on_continue_button_pressed() -> void:
	SceneRouter.start_level(GameState.current_level)
