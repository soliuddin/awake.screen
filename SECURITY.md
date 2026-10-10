# Security

## What this project does and does not do

- Makes **no network requests**. The web page loads only its own three files.
- Stores **nothing**: no cookies, no local storage, no files written.
- Uses **no third-party code, fonts or trackers**.
- Asks only for the screen wake lock (web) or the Windows "keep display on" setting (desktop).
- The web page ships a strict Content Security Policy: no inline scripts or styles, no `eval`, no frames, no forms, no outside hosts.
- The Windows script has no network code, does not write files, and does not use `Invoke-Expression` or download anything.

## Check what you downloaded

`SHA256SUMS` lists the hash of each file in a release. On Windows:

```powershell
Get-FileHash .\windows\StayAwake.ps1 -Algorithm SHA256
```

Compare the result with the matching line in `SHA256SUMS`. The scripts are short and plain text, so you can also read them before running.

## Known limits

- The Windows files are not code-signed, so SmartScreen may show "Windows protected your PC". Choose **More info**, then **Run anyway**, only if the hashes match.
- `Start Stay Awake.bat` starts PowerShell with `-ExecutionPolicy Bypass` for that one process only. It does not change your system policy.
- A `<meta>` Content Security Policy cannot set `frame-ancestors`. GitHub Pages cannot send custom headers, so use a host that reads `_headers` (Netlify, Cloudflare Pages) if you need those too.

## Reporting a vulnerability

Please use GitHub's **Report a vulnerability** button under this repository's **Security** tab so the report stays private. Do not open a public issue for a security problem.
