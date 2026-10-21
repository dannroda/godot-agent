class_name UpgradeCard
extends PanelContainer

signal purchase_requested(upgrade: UpgradeData)

var upgrade: UpgradeData

@onready var icon_rect: TextureRect = %IconRect
@onready var name_label: Label = %NameLabel
@onready var description_label: Label = %DescriptionLabel
@onready var buy_button: Button = %BuyButton


func _ready() -> void:
	buy_button.pressed.connect(_on_buy_button_pressed)


func setup(data: UpgradeData) -> void:
	upgrade = data
	icon_rect.texture = data.icon
	name_label.text = data.display_name
	description_label.text = data.description
	buy_button.text = "%d coins" % data.cost


func refresh(coins: int, owned: bool) -> void:
	if owned:
		buy_button.text = "Owned"
		buy_button.disabled = true
	else:
		buy_button.disabled = coins < upgrade.cost
	modulate = Color(1.0, 1.0, 1.0, 0.6) if owned else Color.WHITE


func _on_buy_button_pressed() -> void:
	purchase_requested.emit(upgrade)
