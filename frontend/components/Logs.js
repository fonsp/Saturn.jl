import { cl } from "../common/ClassTable.js"
import { html, useState, useEffect, useLayoutEffect, useRef, useContext } from "../imports/Preact.js"
import { SimpleOutputBody } from "./TreeView.js"

export const Logs = ({ logs, line_heights }) => {
    return html`
        <pluto-logs-container>
            <pluto-logs style="grid-template-rows: ${line_heights.map((y) => y + "px").join(" ") + " repeat(auto-fill, 15px)"};">
                <div style="grid-row: 1 / 20 "></div>
                ${logs.map((log, i) => {
                    return html`<${Dot} level=${log.level} msg=${log.msg} kwargs=${log.kwargs} x=${i} y=${log.line - 1} /> `
                })}
            </pluto-logs>
        </pluto-logs-container>
    `
}

const mimepair_output = (pair) => html`<${SimpleOutputBody} cell_id=${"adsf"} mime=${pair[1]} body=${pair[0]} persist_js_state=${false} />`

const Dot = ({ msg, kwargs, x, y, level }) => {
    const node_ref = useRef(null)
    // const label_ref = useRef(null)
    // useEffect(() => {
    //     label_ref.current.innerHTML = body
    // }, [body])

    useLayoutEffect(() => {
        node_ref.current.style.gridColumn = `${x + 1}`
        node_ref.current.style.gridRow = `${y + 1}`
    }, [x, y])

    const [inspecting, set_inspecting] = useState(false)
    useLayoutEffect(() => {
        if (inspecting) {
            const f = (e) => {
                if (!e.target.closest || e.target.closest("pluto-log-dot-positioner") !== node_ref.current) {
                    set_inspecting(false)
                }
            }
            window.addEventListener("click", f)
            window.addEventListener("blur", f)

            return () => {
                window.removeEventListener("click", f)
                window.removeEventListener("blur", f)
            }
        }
    }, [inspecting])

    return html` <pluto-log-dot-positioner
        ref=${node_ref}
        class=${cl({ inspecting })}
        onClick=${() => {
            set_inspecting(true)
        }}
    >
        <pluto-log-dot-sizer>
            <pluto-log-dot class=${level}
                >${mimepair_output(msg)}${kwargs.map(
                    ([k, v]) => html` <pluto-log-dot-kwarg><pluto-key>${k}</pluto-key> <pluto-value>${mimepair_output(v)}</pluto-value></pluto-log-dot-kwarg> `
                )}</pluto-log-dot
            >
        </pluto-log-dot-sizer>
    </pluto-log-dot-positioner>`
}
