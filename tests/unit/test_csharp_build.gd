extends "test_case.gd"
## C# del proyecto (m14-07): los errores de dotnet build por archivo y línea.

const CsharpBuild := preload("res://addons/godot_agent/core/csharp_build.gd")
const FIXTURE := "res://tests/fixtures/csharp"


func test_parse_build_output() -> void:
	var project := ProjectSettings.globalize_path("res://")
	var lines := PackedStringArray([
		"%sscripts/Enemy.cs(7,12): error CS0103: The name 'undefinedThing' does not exist in the current context [%sGame.csproj]" % [project, project],
		"%sscripts/Enemy.cs(7,12): error CS0103: The name 'undefinedThing' does not exist in the current context [%sGame.csproj]" % [project, project],
		"%sPlayer.cs(3,1): warning CS0168: unused [%sGame.csproj]" % [project, project],
		"/elsewhere/Lib.cs(1,1): error CS1002: ; expected",
		"Build FAILED.",
	])
	var results := CsharpBuild.parse_build_output(lines)
	assert_eq(results.keys(), ["res://scripts/Enemy.cs", "/elsewhere/Lib.cs"], "rutas del proyecto como res://, sin warnings")
	assert_eq(results["res://scripts/Enemy.cs"].errors, ["line 7: CS0103 The name 'undefinedThing' does not exist in the current context"], "sin repetir y sin el proyecto")


## Con el SDK de .NET instalado, compila el fixture de verdad (en una copia, para no dejar obj/ en el repo).
func test_real_build() -> void:
	if CsharpBuild.CommandResolver.resolve("dotnet").is_empty():
		print("  (sin dotnet: se saltea la compilación real)")
		return
	var copy := ProjectSettings.globalize_path(temp_dir("csharp"))
	for file: String in DirAccess.get_files_at(FIXTURE):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE.path_join(file)), copy.path_join(file))
	assert_eq(CsharpBuild.find_project(copy), copy.path_join("CsFixture.csproj"), "encuentra el .csproj")
	var report: Dictionary = await CsharpBuild.build(copy.path_join("CsFixture.csproj"))
	assert_eq(report.error, "", "dotnet corrió")
	var broken := copy.path_join("Broken.cs")
	assert_true(report.results.has(broken) and str(report.results[broken].errors).contains("line 7: CS0103"), "el error de Broken.cs con su línea · %s" % [report.results])
	assert_false(report.results.has(copy.path_join("Good.cs")), "Good.cs compila")
