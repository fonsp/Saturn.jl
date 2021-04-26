import { html, useRef, useState, useContext } from "../imports/Preact.js"

import { PlutoImage, RawHTMLContainer } from "./CellOutput.js"
import { PlutoContext } from "../common/PlutoContext.js"

// this is different from OutputBody because:
// it does not wrap in <div>. We want to do that in OutputBody for reasons that I forgot (feel free to try and remove it), but we dont want it here
// i think this is because i wrote those css classes with the assumption that pluto cell output is wrapped in a div, and tree viewer contents are not
// whatever
//
// TODO: remove this, use OutputBody instead, and fix the CSS classes so that i all looks nice again
export const SimpleOutputBody = ({ mime, body, cell_id, persist_js_state }) => {
    switch (mime) {
        case "image/png":
        case "image/jpg":
        case "image/jpeg":
        case "image/gif":
        case "image/bmp":
        case "image/svg+xml":
            return html`<${PlutoImage} mime=${mime} body=${body} />`
            break
        case "text/html":
            return html`<${RawHTMLContainer} body=${body} persist_js_state=${persist_js_state} />`
            break
        case "application/vnd.pluto.tree+object":
            return html`<${TreeView} cell_id=${cell_id} body=${body} persist_js_state=${persist_js_state} />`
            break
        case "application/vnd.pluto.table+object":
            return html` <${TableView} cell_id=${cell_id} body=${body} persist_js_state=${persist_js_state} />`
            break
        case "text/plain":
            return html`<pre>${body}</pre>`
        default:
            return html`<pre title="Something went wrong displaying this object">🛑</pre>`
            break
    }
}

const More = ({ on_click_more }) => {
    const [loading, set_loading] = useState(false)

    return html`<jlmore
        class=${loading ? "loading" : ""}
        onclick=${(e) => {
            if (!loading) {
                if (on_click_more() !== false) {
                    set_loading(true)
                }
            }
        }}
        >more</jlmore
    >`
}

const prefix = ({ prefix, prefix_short }) => html`<jlprefix class="long">${prefix}</jlprefix><jlprefix class="short">${prefix_short}</jlprefix>`

export const TreeView = ({ mime, body, cell_id, persist_js_state }) => {
    let pluto_actions = useContext(PlutoContext)
    const node_ref = useRef(null)
    const onclick = (e) => {
        // TODO: this could be reactified but no rush
        let self = node_ref.current
        let clicked = e.target.tagName === "JLPREFIX" ? e.target.parentElement : e.target
        if (clicked !== self && !self.classList.contains("collapsed")) {
            return
        }
        const parent_tree = self.parentElement.closest("jltree")
        if (parent_tree != null && parent_tree.classList.contains("collapsed")) {
            return // and bubble upwards
        }

        self.classList.toggle("collapsed")
    }
    const on_click_more = () => {
        if (node_ref.current.closest("jltree.collapsed") != null) {
            return false
        }
        pluto_actions.reshow_cell(cell_id, body.objectid, 1)
    }

    const mimepair_output = (pair) => html`<${SimpleOutputBody} cell_id=${cell_id} mime=${pair[1]} body=${pair[0]} persist_js_state=${persist_js_state} />`
    const more = html`<r><${More} on_click_more=${on_click_more} /></r>`

    var inner = null
    switch (body.type) {
        case "Pair":
            const r = body.key_value
            return html`<jlpair class=${body.type}
                ><r><k>${mimepair_output(r[0])}</k><v>${mimepair_output(r[1])}</v></r></jlpair
            >`
        case "circular":
            return html`<em>circular reference</em>`
        case "Array":
        case "Set":
        case "Tuple":
            inner = html`${prefix(body)}<jlarray class=${body.type}
                    >${body.elements.map((r) =>
                        r === "more" ? more : html`<r>${body.type === "Set" ? "" : html`<k>${r[0]}</k>`}<v>${mimepair_output(r[1])}</v></r>`
                    )}</jlarray
                >`
            break
        case "Dict":
            inner = html`${prefix(body)}<jldict class=${body.type}
                    >${body.elements.map((r) => (r === "more" ? more : html`<r><k>${mimepair_output(r[0])}</k><v>${mimepair_output(r[1])}</v></r>`))}</jldict
                >`
            break
        case "NamedTuple":
            inner = html`<jldict class=${body.type}
                >${body.elements.map((r) => (r === "more" ? more : html`<r><k>${r[0]}</k><v>${mimepair_output(r[1])}</v></r>`))}</jldict
            >`
            break
        case "struct":
            inner = html`${prefix(body)}<jlstruct>${body.elements.map((r) => html`<r><k>${r[0]}</k><v>${mimepair_output(r[1])}</v></r>`)}</jlstruct>`
            break
    }

    return html`<jltree class="collapsed" onclick=${onclick} ref=${node_ref}>${inner}</jltree>`
}

export const TableView = ({ mime, body, cell_id, persist_js_state }) => {
    let pluto_actions = useContext(PlutoContext)
    const node_ref = useRef(null)

    const mimepair_output = (pair) => html`<${SimpleOutputBody} cell_id=${cell_id} mime=${pair[1]} body=${pair[0]} persist_js_state=${persist_js_state} />`
    const more = (dim) => html`<${More}
        on_click_more=${() => {
            pluto_actions.reshow_cell(cell_id, body.objectid, dim)
        }}
    />`

    const thead =
        body.schema == null
            ? null
            : html`<thead>
                  <tr class="schema-names">
                      ${["", ...body.schema.names].map((x) => html`<th>${x === "more" ? more(2) : x}</th>`)}
                  </tr>
                  <tr class="schema-types">
                      ${["", ...body.schema.types].map((x) => html`<th>${x === "more" ? null : x}</th>`)}
                  </tr>
              </thead>`
    const tbody = html`<tbody>
        ${body.rows.map(
            (row) =>
                html`<tr>
                    ${row === "more"
                        ? html`<td class="jlmore-td" colspan="999">${more(1)}</td>`
                        : html`<th>${row[0]}</th>
                              ${row[1].map((x) => html`<td>${x === "more" ? null : mimepair_output(x)}</td>`)}`}
                </tr>`
        )}
    </tbody>`

    return html`<table class="pluto-table">
        ${thead}${tbody}
    </table>`
}
