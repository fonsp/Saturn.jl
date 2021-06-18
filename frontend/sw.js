// mostly based on https://developers.google.com/web/fundamentals/primers/service-workers

const DEBUG = false
const noop = () => {}
const logger = {
    log: DEBUG ? console.log : noop,
    warn: DEBUG ? console.warn : noop,
    info: DEBUG ? console.info : noop,
}
var CACHE_NAME = "pluto-cache-v3"

self.addEventListener("install", (event) => {
    logger.log("Hello from service worker 👋")
    // Perform install steps
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => {
            logger.log("Opened cache")
        })
    )
})

const allowList = ["www.gstatic.com", "fonts.gstatic.com", "fonts.googleapis.com", "cdn.jsdelivr.net", "cdnjs.cloudflare.com", "unpkg.com"]

function shouldCache(request) {
    const url = new URL(request.url)
    return request.method === "GET" && allowList.includes(url.host) && !url.search.includes("skip_sw")
}

self.addEventListener("fetch", (event) => {
    // if (navigator.userAgent.includes("Firefox")) {
    //     return
    // }
    if (!shouldCache(event.request)) {
        logger.log("skipping cache")
        return
    }
    event.respondWith(
        caches.open(CACHE_NAME).then((cache) =>
            cache.match(event.request).then((response) => {
                if (response != null) {
                    logger.info("CACHE HIT", event.request)
                    return response
                } else {
                    logger.warn("Cache miss", event.request.url)

                    const response_ok = (r) => r != null && r.status === 200

                    const handle_response = (response) => {
                        // Check if we received a valid response
                        if (!response_ok(response)) {
                            return response
                        } else {
                            logger.warn("FETCHED")

                            // Clone the response. A response is a stream
                            // and because we want the browser to consume the response
                            // as well as the cache consuming the response, we need
                            // to clone it so we have two streams.
                            var responseToCache = response.clone()
                            cache.put(event.request, responseToCache)

                            return response
                        }
                    }

                    const proxy_url = new URL("./proxied_lib/" + encodeURIComponent(encodeURIComponent(event.request.url)), location).href

                    logger.info("Proxy url", proxy_url)
                    return fetch(proxy_url)
                        .then((r) => {
                            if (response_ok(r)) {
                                return handle_response(new Response(r.body, r))
                            } else {
                                throw new Error("Failed to proxy through Pluto")
                            }
                        })
                        .catch((e) => {
                            logger.warn(e)
                            return fetch(event.request).then(handle_response)
                        })
                }
            })
        )
    )
})
