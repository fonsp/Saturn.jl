import { html, useContext, useEffect, useMemo, useState } from "../imports/Preact.js"

export const useDelayed = (value, delay = 500) => {
    const [current, set_current] = useState(null)

    useEffect(() => {
        const timer = setTimeout(() => {
            set_current(value)
        }, delay)
        return () => clearTimeout(timer)
    }, [value])

    return current
}

export const ProgressBar = ({ notebook }) => {
    const [recently_running, set_recently_running] = useState([])
    const [currently_running, set_currently_running] = useState([])

    useEffect(
        () => {
            const currently = Object.values(notebook.cell_results).filter((c) => c.running || c.queued)
            set_currently_running(currently)
            if (recently_running.length === 0 || currently.length === 0) {
                set_recently_running(currently)
            }
            console.log(Object.values(notebook.cell_results))
        },
        Object.values(notebook.cell_results).map((c) => c.running || c.queued)
    )

    let progress = recently_running.length === 0 ? 0 : 1 - Math.max(0, currently_running.length - 0.9) / recently_running.length

    const anything = recently_running.length !== 0 && progress !== 1
    const anything_for_a_short_while = useDelayed(anything, 500) ?? false
    // const anything_for_a_long_while = useDelayed(anything, 500)

    if (anything_for_a_short_while && recently_running.length === 0) {
        progress = 1
    }

    console.log(recently_running)

    return html`<loading-bar
        style=${`width: ${100 * progress}vw; opacity: ${anything && anything_for_a_short_while ? 1 : 0}; ${
            anything || anything_for_a_short_while ? "" : "transition: none;"
        }`}
    ></loading-bar>`
}
