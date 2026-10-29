using Godot;

public partial class Good : CharacterBody2D
{
	[Signal] public delegate void HitEventHandler(int damage);

	[Export] public float Speed = 300.0f;

	public override void _PhysicsProcess(double delta)
	{
		Velocity = Input.GetVector("ui_left", "ui_right", "ui_up", "ui_down") * Speed;
		MoveAndSlide();
		GetNodeOrNull<Label>("HUD/Score")?.SetText("0");
		EmitSignal(SignalName.Hit, 5);
		GD.Print(Speed);
	}
}
