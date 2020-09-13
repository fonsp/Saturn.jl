import { html } from "../common/Preact.js"

import { Cell } from "./Cell.js"

export const Notebook = ({
    cells,
    on_update_doc_query,
    on_cell_input,
    on_cell_output_changed,
    on_focus_neighbor,
    disable_input,
    focus_after_creation,
    all_completed_promise,
    selected_friends,
    requests,
    client,
    notebook_id,
}) => {

    // window.addEventListener("notebook-message", (e) => {
    //     console.log('notebook-message received ', e.detail.name)
    //     if (e.detail.callback) e.detail.callback()
    // })

    return html`
        <pluto-notebook>
            ${cells.map(
                (d) => html`<${Cell}
                    ...${d}
                    key=${d.cell_id}
                    on_update_doc_query=${on_update_doc_query}
                    on_change=${(val) => on_cell_input(d, val)}
                    on_update=${on_cell_output_changed}
                    on_focus_neighbor=${on_focus_neighbor}
                    disable_input=${disable_input}
                    focus_after_creation=${focus_after_creation}
                    all_completed_promise=${all_completed_promise}
                    selected_friends=${selected_friends}
                    requests=${requests}
                    client=${client}
                    notebook_id=${notebook_id}
                />`
            )}
        </pluto-notebook>
    `
}
