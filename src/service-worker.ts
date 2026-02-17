/// <reference types="@sveltejs/kit" />
/// <reference no-default-lib="true"/>
/// <reference lib="esnext" />
/// <reference lib="webworker" />

import { build, files, version } from '$service-worker';

const sw = self as unknown as ServiceWorkerGlobalScope;
const CACHE = `quantis-${version}`;
const ASSETS = [...build, ...files];

sw.addEventListener('install', (event) => {
	event.waitUntil(
		caches
			.open(CACHE)
			.then((cache) => cache.addAll(ASSETS))
			.then(() => sw.skipWaiting())
	);
});

sw.addEventListener('activate', (event) => {
	event.waitUntil(
		caches.keys().then(async (keys) => {
			for (const key of keys) {
				if (key !== CACHE) await caches.delete(key);
			}
			sw.clients.claim();
		})
	);
});

sw.addEventListener('fetch', (event) => {
	if (event.request.method !== 'GET') return;

	const url = new URL(event.request.url);

	// No cachear requests a Supabase
	if (url.hostname.includes('supabase')) return;

	const isAsset = ASSETS.includes(url.pathname);

	event.respondWith(
		(async () => {
			const cache = await caches.open(CACHE);

			// Assets: cache-first
			if (isAsset) {
				const cached = await cache.match(event.request);
				if (cached) return cached;
			}

			// Network-first para navegación
			try {
				const response = await fetch(event.request);
				if (response.status === 200) {
					cache.put(event.request, response.clone());
				}
				return response;
			} catch {
				const cached = await cache.match(event.request);
				if (cached) return cached;

				// Fallback para navegación
				if (event.request.mode === 'navigate') {
					const fallback = await cache.match('/200.html');
					if (fallback) return fallback;
				}

				return new Response('Sin conexión', {
					status: 503,
					headers: { 'Content-Type': 'text/plain' }
				});
			}
		})()
	);
});
