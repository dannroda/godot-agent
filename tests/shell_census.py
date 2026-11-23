#!/usr/bin/env python3
"""m11-84: what agents do in the shell instead of the godot.* tools.

Reads the harness session histories (user://godot_agent/sessions/*.jsonl of every project, without the
fake agent's) and, if present, the Claude Code transcripts that the harness launched (entrypoint sdk-ts, with godot.* calls),
and counts each distinct shell command by purpose, with the editor tool that covers it.

    python3 -I tests/shell_census.py [--since 2026-11-23] [--examples 3] [--json out.json]

--since keeps only sessions modified on or after that date: run it again after a release to see whether
the agents moved to the tools. Only reads; it never prints whole commands unless --examples is given.
"""
import argparse
import collections
import datetime
import glob
import json
import os
import re

USERDATA = [
    "~/.local/share/godot/app_userdata",  # Linux
    "~/Library/Application Support/Godot/app_userdata",  # macOS
    "%APPDATA%/Godot/app_userdata",  # Windows
]
CLAUDE_DIRS = ["~/.claude/projects", "~/.claude-profiles/*/projects"]

# (purpose, regex on the command, the godot.* tool that covers it). First match wins.
PURPOSES = [
    ("wait loop", r"\buntil\b|while .*\bsleep\b|^sleep\b|;\s*sleep \d", "editor_wait"),
    ("processes", r"\b(ps|pgrep|pkill|kill|ss|lsof)\b", "stop_scene / game_instance"),
    ("headless tests", r"(--headless|\$G\b|\$GODOT\b).*(test|res://tests|gut|gdunit)", "run_tests"),
    ("headless import", r"--headless.*--import|--import.*--headless", "get_errors / validate_scripts"),
    ("headless script", r"--headless.*(--script|-s )", "get_resource / scene_tree / list_files"),
    ("headless other", r"--headless", "run_scene / export_project"),
    ("grep scenes/resources", r"\b(grep|rg)\b.*(\.tscn|\.tres|\[node|ext_resource|\[connection)", "scene_tree / get_node / dependencies"),
    ("grep symbols", r"\b(grep|rg)\b.*(func |class_name|extends|signal |\^func)", "find_symbols / find_references / read_function"),
    ("grep output/logs", r"\b(grep|rg)\b.*(\.log\b|error|warn)", "get_output (contains) / get_errors"),
    ("grep text", r"\b(grep|rg|ag)\b", "find_in_files"),
    ("find files", r"\bfind\b", "list_files"),
    ("image info", r"\b(file|identify|magick|montage|exiftool)\b", "list_files (image sizes)"),
    ("read file", r"^(cd [^&;]+(&&|;) *)*(cat|sed -n|head|tail|nl|less|wc)\b", "read_function / the agent's Read"),
    ("list dir", r"^(cd [^&;]+(&&|;) *)*(ls|tree|du)\b", "list_files"),
    ("move/copy/delete", r"^(cd [^&;]+(&&|;) *)*(rm|cp|mv)\b", "move_file / copy_file / delete_file"),
    ("git", r"\bgit\b|\bgh\b", "(shell is fine)"),
]


def normalized(command):
    """The same command with or without a leading `cd <project> &&` counts once."""
    return re.sub(r"^\s*cd\s+(\"[^\"]*\"|\S+)\s*(&&|;)\s*", "", command.strip())


def expand(path):
    return os.path.expanduser(os.path.expandvars(path))


def modified_since(path, since):
    return since is None or datetime.date.fromtimestamp(os.path.getmtime(path)) >= since


def harness_commands(since):
    found = {}
    for base in USERDATA:
        for path in glob.glob(expand(base) + "/*/godot_agent/sessions/*.jsonl"):
            if os.path.basename(path).startswith("fake-") or not modified_since(path, since):
                continue
            project = path.split("app_userdata" + os.sep)[-1].split(os.sep)[0]
            with open(path, encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    try:
                        event = json.loads(line)
                    except ValueError:
                        continue
                    update = event.get("update") if isinstance(event, dict) else None
                    if not isinstance(update, dict) or update.get("sessionUpdate") not in ("tool_call", "tool_call_update"):
                        continue
                    raw = update.get("rawInput")
                    if isinstance(raw, dict) and raw.get("command"):
                        command = raw["command"]
                        found.setdefault(normalized(" ".join(map(str, command)) if isinstance(command, list) else str(command)), project)
    return found


def transcript_commands(since):
    found = {}
    godot_calls = collections.Counter()
    for base in CLAUDE_DIRS:
        for path in glob.glob(expand(base) + "/*/*.jsonl"):
            if not modified_since(path, since):
                continue
            launched_by_harness = False
            commands = []
            calls = collections.Counter()
            with open(path, encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    try:
                        event = json.loads(line)
                    except ValueError:
                        continue
                    if event.get("entrypoint") == "sdk-ts":
                        launched_by_harness = True
                    message = event.get("message")
                    if not isinstance(message, dict) or message.get("role") != "assistant":
                        continue
                    for block in message.get("content") or []:
                        if not isinstance(block, dict) or block.get("type") != "tool_use":
                            continue
                        name = block.get("name", "")
                        if name == "Bash":
                            commands.append(str(block.get("input", {}).get("command", "")))
                        elif name.startswith("mcp__godot__"):
                            calls[name[len("mcp__godot__"):]] += 1
            # sdk-ts is any Agent SDK app: a session of the harness also has the editor's godot.* tools.
            if launched_by_harness and calls:
                project = os.path.basename(os.path.dirname(path))
                for command in commands:
                    found.setdefault(normalized(command), project)
                godot_calls.update(calls)
    return found, godot_calls


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--since", type=datetime.date.fromisoformat)
    parser.add_argument("--examples", type=int, default=0)
    parser.add_argument("--json")
    args = parser.parse_args()
    commands = harness_commands(args.since)
    from_transcripts, godot_calls = transcript_commands(args.since)
    for command, project in from_transcripts.items():
        commands.setdefault(command, project)
    counts = collections.Counter()
    examples = collections.defaultdict(list)
    for command in commands:
        purpose, tool = "other", ""
        for name, pattern, covered_by in PURPOSES:
            if re.search(pattern, command, re.M):
                purpose, tool = name, covered_by
                break
        counts[(purpose, tool)] += 1
        if len(examples[purpose]) < args.examples:
            examples[purpose].append(command.replace("\n", " ⏎ ")[:160])
    total = len(commands)
    print("distinct shell commands: %d · godot.* calls in the same transcripts: %d" % (total, sum(godot_calls.values())))
    for (purpose, tool), count in counts.most_common():
        print("%5d  %3d%%  %-22s → %s" % (count, round(100 * count / max(total, 1)), purpose, tool))
        for example in examples[purpose]:
            print("              " + example)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump({"total": total, "purposes": {p: c for (p, _), c in counts.items()}, "godot_calls": godot_calls}, handle, indent=1)


if __name__ == "__main__":
    main()
