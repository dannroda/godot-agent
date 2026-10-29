using Godot;

public partial class Broken : Node2D
{
	public override void _Ready()
	{
		GD.Print(undefinedThing);
	}
}
