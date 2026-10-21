extends Node

signal coin_collected(amount: int)
signal player_damaged(amount: int, remaining: int)
signal player_died
signal enemy_killed(enemy: Node2D, score: int)
signal checkpoint_reached(checkpoint_position: Vector2)
signal level_completed(level_id: String)
signal upgrade_purchased(upgrade_id: StringName)
signal game_paused(is_paused: bool)
signal screen_shake_requested(strength: float, duration: float)
