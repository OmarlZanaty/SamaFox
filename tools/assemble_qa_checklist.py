# -*- coding: utf-8 -*-
"""Injects qa_data.json into the checklist template and writes the artifact file."""
import io, os

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)

with io.open(os.path.join(here, 'qa_data.json'), encoding='utf-8') as f:
    payload = f.read()

# The payload is embedded in a <script type="application/json"> block: the only
# sequence that could close it early is "</script>" in the text.
assert '</script>' not in payload.lower(), 'payload would close its own script tag'

with io.open(os.path.join(here, 'qa_checklist_template.html'), encoding='utf-8') as f:
    html = f.read()

assert html.count('__DATA__') == 1
html = html.replace('__DATA__', payload)

out = os.path.join(root, 'qa_checklist_ar.html')
with io.open(out, 'w', encoding='utf-8', newline='\n') as f:
    f.write(html)

print('wrote', out, len(html), 'chars')
