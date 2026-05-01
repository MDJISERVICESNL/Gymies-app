import os
from pathlib import Path

source = Path(os.environ.get('WEB_PHP', '/var/www/mdjiservices.nl/laravel/routes/web.php'))
snippet = Path(os.environ.get('SNIPPET_PATH', 'routes_trainmaat_snippet.php'))
out = Path(os.environ.get('OUT_PATH', 'web.php.trainmaat.fixed'))

start_marker = "Route::prefix('api/trainmaat')"
end_marker = "\n});"

wt = source.read_text()
st = snippet.read_text()

start = st.find(start_marker)
if start == -1:
    raise SystemExit('Could not find api/trainmaat block start in snippet')
line_start = st.rfind("\n", 0, start) + 1
end = st.find(end_marker, start)
if end == -1:
    raise SystemExit('Could not find api/trainmaat block end in snippet')
new_block = st[line_start : end + len(end_marker)]

ws = wt.find(start_marker)
if ws == -1:
    fixed = wt + "\n\n" + new_block + "\n"
else:
    wline_start = wt.rfind("\n", 0, ws) + 1
    we = wt.find(end_marker, ws)
    if we == -1:
        raise SystemExit('Could not find api/trainmaat block end in web.php')
    fixed = wt[:wline_start] + new_block + wt[we + len(end_marker) :]

out.write_text(fixed)
print(f'Wrote fixed copy: {out}')
