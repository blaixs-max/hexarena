// HexArena PWA + Fullscreen overlay injector
// Bu dosya Godot re-export'larında silinmez (Godot sadece index.html'i yeniden yazar)
// head_include'a `<script src="hexarena-pwa.js" defer></script>` eklenmesi yeterli

(function () {
	// === Meta tags + manifest ===
	const metas = [
		{ name: 'apple-mobile-web-app-capable', content: 'yes' },
		{ name: 'apple-mobile-web-app-status-bar-style', content: 'black-translucent' },
		{ name: 'apple-mobile-web-app-title', content: 'HexArena' },
		{ name: 'mobile-web-app-capable', content: 'yes' },
		{ name: 'theme-color', content: '#0a1421' },
		{ name: 'screen-orientation', content: 'landscape' },
		{ name: 'x5-orientation', content: 'landscape' },
	];
	metas.forEach(m => {
		const tag = document.createElement('meta');
		tag.name = m.name;
		tag.content = m.content;
		document.head.appendChild(tag);
	});
	const manifest = document.createElement('link');
	manifest.rel = 'manifest';
	manifest.href = 'manifest.json';
	document.head.appendChild(manifest);

	const viewportTag = document.querySelector('meta[name="viewport"]');
	if (viewportTag) {
		viewportTag.content = 'width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, viewport-fit=cover';
	}
	const titleTag = document.querySelector('title');
	if (titleTag) titleTag.textContent = 'HexArena - 3v3 Soccer';

	// === Stylesheet ===
	const style = document.createElement('style');
	style.textContent = `
#fs-overlay {
	position: fixed;
	inset: 0;
	background: radial-gradient(circle at 50% 35%, #0e3a23 0%, #0a1620 70%, #050a10 100%);
	display: flex;
	flex-direction: column;
	align-items: center;
	justify-content: center;
	z-index: 9999;
	font-family: 'Segoe UI', 'Helvetica Neue', Arial, sans-serif;
	color: #fff;
	transition: opacity 0.4s ease;
}
#fs-overlay.fade-out { opacity: 0; pointer-events: none; }
.fs-title {
	font-size: clamp(2.4rem, 8vw, 5rem);
	font-weight: 900;
	letter-spacing: 0.08em;
	margin: 0 0 0.4rem 0;
	background: linear-gradient(180deg, #ffd95a 0%, #c08720 100%);
	-webkit-background-clip: text;
	background-clip: text;
	-webkit-text-fill-color: transparent;
	text-shadow: 0 6px 20px rgba(217, 179, 67, 0.35);
	filter: drop-shadow(0 2px 0 rgba(0,0,0,0.4));
}
.fs-subtitle {
	font-size: clamp(0.85rem, 2vw, 1.05rem);
	color: rgba(255, 255, 255, 0.75);
	margin: 0 0 2.4rem 0;
	letter-spacing: 0.04em;
}
#fs-button {
	background: linear-gradient(180deg, #f08c2a 0%, #c95f0e 100%);
	border: 3px solid #ffb960;
	color: #fff;
	padding: 1.05rem 2.4rem;
	font-size: clamp(1rem, 2.4vw, 1.25rem);
	font-weight: 700;
	letter-spacing: 0.06em;
	border-radius: 14px;
	cursor: pointer;
	box-shadow: 0 6px 0 rgba(0,0,0,0.35), 0 12px 28px rgba(241, 140, 42, 0.35), inset 0 2px 4px rgba(255,255,255,0.4);
	transition: transform 0.08s ease, box-shadow 0.08s ease;
	user-select: none;
	-webkit-tap-highlight-color: transparent;
}
#fs-button:active {
	transform: translateY(3px);
	box-shadow: 0 3px 0 rgba(0,0,0,0.35), 0 6px 14px rgba(241, 140, 42, 0.3), inset 0 2px 4px rgba(255,255,255,0.4);
}
`;
	document.head.appendChild(style);

	// === Fullscreen helpers ===
	function applyFullscreenCSS() {
		document.documentElement.style.height = '100%';
		document.body.style.position = 'fixed';
		document.body.style.top = '0';
		document.body.style.left = '0';
		document.body.style.right = '0';
		document.body.style.bottom = '0';
		document.body.style.width = '100vw';
		document.body.style.height = '100vh';
		document.body.style.overflow = 'hidden';
		document.body.style.margin = '0';
		setTimeout(() => window.scrollTo(0, 1), 100);
	}

	async function tryEnterFullscreen() {
		const elem = document.documentElement;
		try {
			if (elem.requestFullscreen) {
				await elem.requestFullscreen({ navigationUI: 'hide' });
			} else if (elem.webkitRequestFullscreen) {
				elem.webkitRequestFullscreen(Element.ALLOW_KEYBOARD_INPUT);
			} else if (elem.msRequestFullscreen) {
				elem.msRequestFullscreen();
			}
		} catch (err) {
			console.warn('Fullscreen API failed:', err);
		}
		applyFullscreenCSS();
		try {
			if (screen.orientation && typeof screen.orientation.lock === 'function') {
				await screen.orientation.lock('landscape').catch(() => {});
			}
		} catch (e) { /* iOS reddedebilir */ }
	}

	// === Overlay HTML — Godot wasm yüklenmeden önce göster ===
	function injectOverlay() {
		const isStandalone = (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) || window.navigator.standalone === true;
		if (isStandalone) {
			applyFullscreenCSS();
			return;
		}
		const overlay = document.createElement('div');
		overlay.id = 'fs-overlay';
		overlay.innerHTML = `
			<h1 class="fs-title">HEXARENA</h1>
			<p class="fs-subtitle">3 vs 3 hızlı tempo futbol</p>
			<button id="fs-button" type="button">TAM EKRAN MODUNA GEÇ</button>
		`;
		document.body.insertBefore(overlay, document.body.firstChild);
		document.getElementById('fs-button').addEventListener('click', async () => {
			await tryEnterFullscreen();
			overlay.classList.add('fade-out');
			setTimeout(() => overlay.remove(), 450);
		});
		window.addEventListener('orientationchange', () => {
			setTimeout(() => window.scrollTo(0, 1), 100);
		});
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', injectOverlay);
	} else {
		injectOverlay();
	}
})();
