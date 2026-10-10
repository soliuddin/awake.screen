# Stay Awake

One glowing button that keeps your screen awake until you turn it off. Works as a web page on any device, and as a frameless floating button on Windows. The button is a colour-cycling light show while it holds the screen awake, and turns red when it is off.

## Web page

Open `index.html` in a browser, or host the folder (see below), then tap the button. The light show runs while the screen is held awake. Tap again to turn it off.

- Uses the browser's Screen Wake Lock. If a browser lacks it, a tiny hidden video keeps the display on instead.
- Keep the tab open and visible. Browsers release the lock when a tab is hidden, and the page takes it back when you return.
- **Float window** (desktop Chrome and Edge): moves the button into a small always-on-top window so you can work in other tabs. The title bar of that window is drawn by the browser and cannot be hidden.
- Respects the system "reduce motion" setting.
- **Install as an app or shortcut:** In Chrome or Edge use the install icon in the address bar, or the menu's **Install** / **Create shortcut** option. The page ships a web app manifest and PNG icons (`icons/`), so the shortcut shows the Stay Awake icon. The page must be opened from a web address (for example GitHub Pages), not from a file on disk, for installing to work.

## Windows floating button

Files in `windows/`. Keep both together.

1. Double-click `Start Stay Awake.bat`.
2. A round button appears at the bottom-right of the screen with no window frame.
3. Left click turns keep-awake on or off, drag moves it, right click quits.

Nothing to install. It uses PowerShell, which ships with Windows.

For a desktop shortcut with the Stay Awake icon, double-click `Create Desktop Shortcut.bat` once (keep it in the same folder as the other files).

## Host it on GitHub Pages

1. Create a new repository and upload everything in this folder.
2. Go to **Settings > Pages**.
3. Under **Build and deployment**, choose **Deploy from a branch**, pick `main` and `/ (root)`, then save.
4. Your page appears at `https://<your-username>.github.io/<repository>/`.

## Security

No network requests, no storage, no third-party code, and a strict Content Security Policy. See [SECURITY.md](SECURITY.md) for details, checksums and how to report a problem.

## Files

| File | Purpose |
| --- | --- |
| `index.html`, `style.css`, `app.js` | The web page |
| `manifest.webmanifest`, `icons/` | Lets browsers install the page as an app with its icon |
| `_headers` | Extra security headers for Netlify and Cloudflare Pages |
| `windows/StayAwake.ps1` | The Windows floating button |
| `windows/Start Stay Awake.bat` | Double-click launcher for the script |
| `windows/Create Desktop Shortcut.bat`, `windows/stay-awake.ico` | Makes a desktop shortcut with the icon |
| `SHA256SUMS` | Hashes of the files above |

## License

MIT. See [LICENSE](LICENSE).
