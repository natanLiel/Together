# Build

`index.html` is generated. Do not edit it by hand — the next build overwrites it.

    pwsh build/build.ps1     # assembles build/parts/app-template.rebuilt.dc.html from source + parts
    pwsh build/apply.ps1     # packs that template into index.html and re-attaches the bar layer

* `build/source/Together.dc.html` — the Claude Design export this app is built from.
* `build/parts/` — the pieces the build splices in: screens, styles, logic, the roster, the bar layer.
* `build/tools/` — palette extraction from photos, app icons, media resizing, a local server on :5731.

Requires PowerShell (Windows PowerShell 5.1 or pwsh).
