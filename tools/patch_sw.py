# Post-export patch for the Godot-generated service worker.
#
# Godot's web_pwa template serves navigation requests cache-first, so an
# installed PWA can keep launching an old build indefinitely. This patch
# flips navigation requests to network-first (cache is the offline
# fallback), so every launch picks up the newest deploy.
#
# The full atomic-update story lives in the loading shell's own version ping:
# after the game starts, the page checks for a newer build and reloads once if
# it finds one - number, engine and game data landing together, without the
# service worker forcing navigation from under a running session.
import sys

path = sys.argv[1]
src = open(path).read()

if "PWC PATCH" in src:
    print("patch_sw: already patched")
    sys.exit(0)

anchor = "const cache = await caches.open(CACHE_NAME)"
inject = anchor + """

			// PWC PATCH: navigation requests go network-first so an installed
			// app always picks up the newest build; cache is the fallback.
			if (isNavigate) {
				try {
					const response = await self.fetch(event.request)
					if (response && response.ok) {
						await cache.put(event.request, response.clone())
						return response
					}
				} catch (e) { /* offline: fall through to cache */ }
			}
			// PWC PATCH (2): the engine files do the same. index.html is
			// network-first on navigation, but a cache-first pck/wasm would
			// keep an installed app running an old build forever. The shell's
			// own build ping fetches index.html as a plain GET, which must
			// reach the network too: the install-time cache holds index.html
			// under its literal path (navigations cache the root URL), so a
			// cache-first answer compares the live build against a dead one.
			// Offline, the cache still answers.
			const isEngineFile = /\\.(pck|wasm|zip|html|js)$/.test(local || url)
			if (isEngineFile) {
				try {
					const response = await self.fetch(event.request)
					if (response && response.ok) {
						await cache.put(event.request, response.clone())
						return response
					}
				} catch (e) { /* offline: fall through to cache */ }
			}"""

if anchor not in src:
    print("patch_sw: anchor not found in " + path, file=sys.stderr)
    sys.exit(1)

src = src.replace(anchor, inject, 1)

# The new worker must take over immediately. Without skipWaiting it waits for
# every tab of the site to close before activating, and a phone that keeps the
# game open sits on a dead worker serving an old build for days - the build
# ping reloads into the same stale cache. claim() hands the open page to the
# fresh worker the moment it activates.
src = src.replace(
	"event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)));",
	"event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)).then(() => self.skipWaiting()));", 1)
src = src.replace(
	"return ('navigationPreload' in self.registration) ? self.registration.navigationPreload.enable() : Promise.resolve();",
	"return (('navigationPreload' in self.registration) ? self.registration.navigationPreload.enable() : Promise.resolve()).then(() => self.clients.claim());", 1)

if "self.skipWaiting()" not in src or "self.clients.claim()" not in src:
	print("patch_sw: take-over injection failed in " + path, file=sys.stderr)
	sys.exit(1)

open(path, "w").write(src)
print("patch_sw: service worker now network-first for navigation")
