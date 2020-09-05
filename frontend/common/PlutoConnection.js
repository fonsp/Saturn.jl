import { pack, unpack } from "./MsgPack.js"
import "./Polyfill.js"

const do_next = async (queue) => {
    const next = queue[0]
    await next()
    queue.shift()
    if (queue.length > 0) {
        await do_next(queue)
    }
}

/**
 * @returns {{current: Promise<any>, resolve: Function}}
 */
export const resolvable_promise = () => {
    let resolve = () => {}
    const p = new Promise((r) => {
        resolve = r
    })
    return {
        current: p,
        resolve: resolve,
    }
}

const get_unique_short_id = () => crypto.getRandomValues(new Uint32Array(1))[0].toString(36)

const socket_is_alright = (socket) => socket.readyState != WebSocket.OPEN && socket.readyState != WebSocket.CONNECTING










start_socket_connection(connect_metadata) {
    return new Promise(async (res) => {
        const secret = await (
            await fetch("websocket_url_please", {
                method: "GET",
                cache: "no-cache",
                redirect: "follow",
                referrerPolicy: "no-referrer",
            })
        ).text()
        this.psocket = new WebSocket(
            document.location.protocol.replace("http", "ws") + "//" + document.location.host + document.location.pathname.replace("/edit", "/") + secret
        )
        this.psocket.onmessage = (e) => {
            this.task_queue.push(async () => {
                await this.handle_message(e)
            })
            if (this.task_queue.length == 1) {
                do_next(this.task_queue)
            }
        }
        this.psocket.onerror = (e) => {
            console.error("SOCKET ERROR", new Date().toLocaleTimeString())
            console.error(e)

            this.start_waiting_for_connection()
        }
        this.psocket.onclose = (e) => {
            console.warn("SOCKET CLOSED", new Date().toLocaleTimeString())
            console.log(e)

            this.start_waiting_for_connection()
        }
        this.psocket.onopen = () => {
            console.log("Socket opened", new Date().toLocaleTimeString())
            this.send("connect", {}, connect_metadata).then((u) => {
                this.plutoENV = u.message.ENV
                // TODO: don't check this here
                if (connect_metadata.notebook_id && !u.message.notebook_exists) {
                    // https://github.com/fonsp/Pluto.jl/issues/55
                    document.location.href = "./"
                    return
                }
                this.on_connection_status(true)
                res(this)
            })
        }
        console.log("Waiting for socket to open...")
    })
}


const create_ws = (address, on_update) => {
    const client_id = get_unique_short_id()
    const sent_requests = {}

    return new Promise((resolve_socket, reject_socket) => {
        const socket = new WebSocket(address)
        socket.onmessage = async (event) => {
            try {
                const buffer = await event.data.arrayBuffer()
                const buffer_sliced = buffer.slice(0, buffer.byteLength - MSG_DELIM.length)
                const update = msgpack.decode(new Uint8Array(buffer_sliced))
                const by_me = update.initiator_id && update.initiator_id == client_id
                const request_id = update.request_id
                if (by_me && request_id) {
                    const request = sent_requests[request_id]
                    if (request) {
                        request(update.body)
                        delete sent_requests[request_id]
                        return
                    }
                }
                on_update(update, by_me)
            } catch (ex) {
                console.error("Failed to process update!", ex)
                console.log(event)

                alert(
                    `Something went wrong!\n\nPlease open an issue on https://github.com/fonsp/Pluto.jl with this info:\n\nFailed to process update\n${ex}\n\n${event}`
                )
            }
        }
        socket.onerror = (e) => {
            console.warn("SOCKET ERROR")
            console.log(e)
            reject_socket(e)
        }
        socket.onclose = (e) => {
            console.warn("SOCKET CLOSED")
            console.log(e)
            reject_socket(e)
        }
        socket.onopen = () => resolve_socket(socket)
    })
}



















export class PlutoConnection {
    async ping() {
        const response = await (
            await fetch("ping", {
                method: "GET",
                cache: "no-cache",
                redirect: "follow",
                referrerPolicy: "no-referrer",
            })
        ).text()
        if (response == "OK!") {
            return response
        } else {
            throw response
        }
    }

    start_waiting_for_connection() {
        if (!socket_is_alright(this.psocket)) {
            setTimeout(() => {
                if (!socket_is_alright(this.psocket)) {
                    // check twice with a 1sec interval because sometimes it just complains for a short while

                    const start_reconnecting = () => {
                        this.on_connection_status(false)
                        this.try_close_socket_connection()
                        // TODO
                    }

                    this.ping()
                        .then(() => {
                            if (this.psocket.readyState !== WebSocket.OPEN) {
                                start_reconnecting()
                            }
                        })
                        .catch(() => {
                            console.error("Ping failed")
                            start_reconnecting()
                        })
                }
            }, 1000)
        }
    }

    /**
     *
     * @param {string} message_type
     * @param {Object} body
     * @param {{notebook_id?: string, cell_id?: string}} metadata
     * @param {boolean} create_promise If true, returns a Promise that resolves with the server response. If false, the response will go through the on_update method of this instance.
     * @returns {(undefined|Promise<Object>)}
     */
    send(message_type, body = {}, metadata = {}, create_promise = true) {
        const request_id = get_unique_short_id()

        const message = {
            type: message_type,
            client_id: this.client_id,
            request_id: request_id,
            body: body,
            ...metadata,
        }

        var p = undefined

        if (create_promise) {
            const rp = resolvable_promise()
            p = rp.current

            this.sent_requests[request_id] = rp.resolve
        }

        const encoded = pack(message)
        const to_send = new Uint8Array(encoded.length + this.MSG_DELIM.length)
        to_send.set(encoded, 0)
        to_send.set(this.MSG_DELIM, encoded.length)
        this.psocket.send(to_send)

        return p
    }

    async handle_message(event) {
        try {
            const buffer = await event.data.arrayBuffer()
            const buffer_sliced = buffer.slice(0, buffer.byteLength - this.MSG_DELIM.length)
            const update = unpack(new Uint8Array(buffer_sliced))
            const by_me = "initiator_id" in update && update.initiator_id == this.client_id
            const request_id = update.request_id

            if (by_me && request_id) {
                const request = this.sent_requests[request_id]
                if (request) {
                    request(update)
                    delete this.sent_requests[request_id]
                    return
                }
            }
            this.on_update(update, by_me)
        } catch (ex) {
            console.error("Failed to process update!", ex)
            console.log(event)

            alert(
                `Something went wrong!\n\nPlease open an issue on https://github.com/fonsp/Pluto.jl with this info:\n\nFailed to process update\n${ex}\n\n${event}`
            )
        }
    }

    start_socket_connection(connect_metadata) {
        return new Promise(async (res) => {
            const secret = await (
                await fetch("websocket_url_please", {
                    method: "GET",
                    cache: "no-cache",
                    redirect: "follow",
                    referrerPolicy: "no-referrer",
                })
            ).text()
            this.psocket = new WebSocket(
                document.location.protocol.replace("http", "ws") + "//" + document.location.host + document.location.pathname.replace("/edit", "/") + secret
            )
            this.psocket.onmessage = (e) => {
                this.task_queue.push(async () => {
                    await this.handle_message(e)
                })
                if (this.task_queue.length == 1) {
                    do_next(this.task_queue)
                }
            }
            this.psocket.onerror = (e) => {
                console.error("SOCKET ERROR", new Date().toLocaleTimeString())
                console.error(e)

                this.start_waiting_for_connection()
            }
            this.psocket.onclose = (e) => {
                console.warn("SOCKET CLOSED", new Date().toLocaleTimeString())
                console.log(e)

                this.start_waiting_for_connection()
            }
            this.psocket.onopen = () => {
                console.log("Socket opened", new Date().toLocaleTimeString())
                this.send("connect", {}, connect_metadata).then((u) => {
                    this.plutoENV = u.message.ENV
                    // TODO: don't check this here
                    if (connect_metadata.notebook_id && !u.message.notebook_exists) {
                        // https://github.com/fonsp/Pluto.jl/issues/55
                        document.location.href = "./"
                        return
                    }
                    this.on_connection_status(true)
                    res(this)
                })
            }
            console.log("Waiting for socket to open...")
        })
    }

    try_close_socket_connection() {
        this.psocket.close(1000, "byebye")
    }

    initialize(on_establish_connection, connect_metadata = {}) {
        this.ping()
            .then(async () => {
                await this.start_socket_connection(connect_metadata)
                on_establish_connection(this)
            })
            .catch(() => {
                this.on_connection_status(false)
            })

        window.addEventListener("beforeunload", (e) => {
            console.warn("unloading 👉 disconnecting websocket")
            this.psocket.onclose = undefined
            this.try_close_socket_connection()
        })
    }

    constructor(on_update, on_connection_status) {
        this.on_update = on_update
        this.on_connection_status = on_connection_status

        this.task_queue = []
        this.psocket = null
        this.MSG_DELIM = new TextEncoder().encode("IUUQ.km jt ejggjdvmu vhi")
        this.client_id = get_unique_short_id()
        this.sent_requests = {}
        this.pluto_version = "unknown"
        this.julia_version = "unknown"
    }

    fetch_pluto_versions() {
        const github_promise = fetch("https://api.github.com/repos/fonsp/Pluto.jl/releases", {
            method: "GET",
            mode: "cors",
            cache: "no-cache",
            headers: {
                "Content-Type": "application/json",
            },
            redirect: "follow",
            referrerPolicy: "no-referrer",
        })
            .then((response) => {
                return response.json()
            })
            .then((response) => {
                return response[0].tag_name
            })

        const pluto_promise = this.send("get_version").then((u) => {
            this.pluto_version = u.message.pluto
            this.julia_version = u.message.julia
            return this.pluto_version
        })

        return Promise.all([github_promise, pluto_promise])
    }

    // TODO: reconnect with a delay if the last request went poorly
    // this would avoid hanging UI when the connection is lost maybe?
}
