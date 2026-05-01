import os
import os
from pathlib import Path
import re

web = Path(os.environ.get('WEB_PHP', '/var/www/mdjiservices.nl/laravel/routes/web.php'))
snippet = Path(os.environ.get('SNIPPET_PATH', 'routes_trainmaat_snippet.php'))

wt = web.read_text()
st = snippet.read_text()

pattern = r"Route::prefix\('api/trainmaat'\)->group\(function \(\) \{[\s\S]*?\n\}\);"

m = re.search(pattern, st)
if not m:
    raise SystemExit('Could not extract api/trainmaat block from snippet')
new_block = m.group(0)

m2 = re.search(pattern, wt)
if m2:
    wt = wt[:m2.start()] + new_block + wt[m2.end():]
else:
    wt = wt + "\n\n" + new_block + "\n"

web.write_text(wt)
print('TrainMaat API block replaced successfully')
