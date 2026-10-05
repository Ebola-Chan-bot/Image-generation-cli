// Service Worker：缓存应用外壳供离线使用，API 请求始终走网络不缓存
const 外壳缓存名 = 'ai图像生成网页版-外壳-v4';
const 外壳文件 = ['./', './index.html', './清单.webmanifest', './图标192.png', './图标512.png'];

self.addEventListener('install', (事件) => {
	事件.waitUntil(caches.open(外壳缓存名).then((缓存) => 缓存.addAll(外壳文件)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (事件) => {
	事件.waitUntil(caches.keys().then((全部键) => Promise.all(全部键.filter((键) => 键 !== 外壳缓存名).map((键) => caches.delete(键)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', (事件) => {
	const 请求 = 事件.request;
	// API 调用与非 GET 请求一律直连网络，绝不缓存（避免缓存到带密钥的响应或过期图像）
	if (请求.method !== 'GET' || new URL(请求.url).origin !== self.location.origin) { return; }
	事件.respondWith(caches.match(请求).then((命中) => 命中 || fetch(请求).then((响应) => {
		const 副本 = 响应.clone();
		caches.open(外壳缓存名).then((缓存) => 缓存.put(请求, 副本));
		return 响应;
	})));
});
