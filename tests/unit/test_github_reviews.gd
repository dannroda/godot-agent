extends "test_case.gd"
## GitHub con gh (m11-10): el repo del remote y los comentarios de un PR como hallazgos.

const GithubReviews := preload("res://addons/godot_agent/core/github_reviews.gd")


func test_repo_from_remote() -> void:
	assert_eq(GithubReviews.repo_from_remote("git@github.com:dannroda/godot-agent.git"), "dannroda/godot-agent", "ssh")
	assert_eq(GithubReviews.repo_from_remote("https://github.com/dannroda/godot-agent\n"), "dannroda/godot-agent", "https sin .git")
	assert_eq(GithubReviews.repo_from_remote("https://gitlab.com/a/b.git"), "", "otro host")


func test_comments_to_findings() -> void:
	var comments := [
		{"path": "game/player.gd", "line": 12, "body": "Use a constant here.\nIt is tuned often.", "user": {"login": "reviewer"}},
		{"path": "game/player.gd", "line": 12, "body": "Agreed", "in_reply_to_id": 1},
		{"path": "game/hud.gd", "line": null, "original_line": 4, "body": "Outdated but still true"},
		{"path": "README.md", "line": 1, "body": "Outside the project"},
		{"path": "game/empty.gd", "line": 3, "body": "  "},
	]
	var findings := GithubReviews.comments_to_findings(comments, "game")
	assert_eq(findings.map(func(f: Dictionary) -> String: return "%s:%d %s" % [f.path, f.line, f.title]),
		["res://player.gd:12 Use a constant here.", "res://hud.gd:4 Outdated but still true"], "sin respuestas, fuera del proyecto ni vacíos; con la línea original si quedó desactualizado")
	assert_true(str(findings[0].body).ends_with("@reviewer on GitHub"), "con quién lo escribió")
	assert_eq(GithubReviews.comments_to_findings([{"path": "a.gd", "line": 2, "body": "x"}], "")[0].path, "res://a.gd", "proyecto en la raíz del repo")
