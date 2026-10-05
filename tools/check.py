"""Compila todos los scripts GDScript con --check-only y muestra los errores reales
(ignora los avisos por autoloads, que no se cargan en este modo)."""
import glob, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = r"C:\Users\juanm\work\project-night-shift\.tools\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"
IGNORE = re.compile(r"Identifier not found: (SaveGame|Audio|Controls)|Failed to compile depended|Failed to load script")
found = 0
seen = set()
for f in sorted(glob.glob(os.path.join(ROOT, "**", "*.gd"), recursive=True)):
    rel = os.path.relpath(f, ROOT).replace("\\", "/")
    out = subprocess.run([GODOT, "--headless", "--path", ROOT, "--check-only", "--script", "res://" + rel],
                         capture_output=True, text=True, encoding="utf-8", errors="replace").stderr
    lines = out.splitlines()
    for i, l in enumerate(lines):
        if "SCRIPT ERROR" in l and not IGNORE.search(l):
            at = lines[i + 1].strip() if i + 1 < len(lines) else ""
            key = (l.strip(), at)
            if key in seen:
                continue
            seen.add(key)
            print(l.strip().replace("SCRIPT ERROR: ", ""), "|", at.replace("at: GDScript::reload ", ""))
            found += 1
print("errores:", found)
sys.exit(1 if found else 0)
