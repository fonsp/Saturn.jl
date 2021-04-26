import { PlutoContext } from "../common/PlutoContext.js"
import { html, useContext, useEffect, useMemo, useState } from "../imports/Preact.js"

import { Cell } from "./Cell.js"

let CellMemo = ({
    cell_result,
    cell_input,
    cell_input_local,
    notebook_id,
    on_update_doc_query,
    on_cell_input,
    on_focus_neighbor,
    selected,
    selected_cells,
    focus_after_creation,
    force_hide_input,
    is_process_ready,
    disable_input,
}) => {
    const selected_cells_diffable_primitive = (selected_cells || []).join("")
    const { body, last_run_timestamp, mime, persist_js_state, rootassignee } = cell_result?.output || {}
    const logs = cell_result?.logs ?? []
    const { queued, running, runtime, errored } = cell_result || {}
    const { cell_id, code, code_folded } = cell_input || {}
    return useMemo(() => {
        return html`
            <${Cell}
                cell_result=${cell_result}
                cell_input=${cell_input}
                cell_input_local=${cell_input_local}
                notebook_id=${notebook_id}
                on_update_doc_query=${on_update_doc_query}
                on_change=${(val) => on_cell_input(cell_input.cell_id, val)}
                on_focus_neighbor=${on_focus_neighbor}
                selected=${selected}
                selected_cells=${selected_cells}
                force_hide_input=${force_hide_input}
                focus_after_creation=${focus_after_creation}
                is_process_ready=${is_process_ready}
                disable_input=${disable_input}
            />
        `
    }, [
        cell_id,
        queued,
        running,
        runtime,
        errored,
        body,
        last_run_timestamp,
        mime,
        persist_js_state,
        rootassignee,
        logs,
        code,
        code_folded,
        cell_input_local,
        notebook_id,
        on_update_doc_query,
        on_cell_input,
        on_focus_neighbor,
        selected,
        selected_cells_diffable_primitive,
        force_hide_input,
        focus_after_creation,
        is_process_ready,
        disable_input,
    ])
}

/**
 * We render all cell outputs directly when the page loads. Rendering cell *inputs* can slow down the initial page load significantly, so we delay rendering them using this heuristic function to determine the length of the delay (as a function of the number of cells in the notebook).
 * @param {Number} num_cells
 */
const render_cell_inputs_delay = (num_cells) => 100 + 10 * num_cells
const render_cell_outputs_delay = (num_cells) => (num_cells > 20 ? 100 : 0)
/**
 * The first <x> cells will bypass the {@link render_cell_inputs_delay} heuristic and render directly.
 */
const render_cell_inputs_minimum = 5
const render_cell_outputs_minimum = 20

/**
 * @param {{
 *  notebook: import("./Editor.js").NotebookData,
 *  cell_inputs_local: { [uuid: string]: import("./Editor.js").CellInputData },
 *  on_update_doc_query: any,
 *  on_cell_input: any,
 *  on_focus_neighbor: any,
 *  last_created_cell: string,
 *  selected_cells: Array<string>,
 *  is_initializing: boolean,
 *  is_process_ready: boolean,
 *  disable_input: any,
 * }} props
 * */
export const Notebook = ({
    notebook,
    cell_inputs_local,
    on_update_doc_query,
    on_cell_input,
    on_focus_neighbor,
    last_created_cell,
    selected_cells,
    is_initializing,
    is_process_ready,
    disable_input,
}) => {
    let pluto_actions = useContext(PlutoContext)

    // Add new cell when the last cell gets deleted
    useEffect(() => {
        // This might look kinda silly...
        // and it is... but it covers all the cases... - DRAL
        if (notebook.cell_order.length === 0 && !is_initializing) {
            pluto_actions.add_remote_cell_at(0)
        }
    }, [is_initializing, notebook.cell_order.length])

    // Only render the notebook partially during the first few seconds
    const [cell_inputs_delayed, set_cell_inputs_delayed] = useState(true)
    const [cell_outputs_delayed, set_cell_outputs_delayed] = useState(true)

    useEffect(() => {
        if (cell_inputs_delayed && notebook.cell_order.length > 0) {
            setTimeout(() => {
                set_cell_inputs_delayed(false)
            }, render_cell_inputs_delay(notebook.cell_order.length))
        }
    }, [cell_inputs_delayed, notebook.cell_order.length])
    useEffect(() => {
        if (cell_outputs_delayed && notebook.cell_order.length > 0) {
            setTimeout(() => {
                set_cell_outputs_delayed(false)
            }, render_cell_outputs_delay(notebook.cell_order.length))
        }
    }, [cell_outputs_delayed, notebook.cell_order.length])

    return html`
        <pluto-notebook id=${notebook.notebook_id}>
            ${notebook.cell_order
                .filter((_, i) => !(cell_outputs_delayed && i > render_cell_outputs_minimum))
                .map(
                    (cell_id, i) => html`<${CellMemo}
                        key=${cell_id}
                        cell_result=${notebook.cell_results[cell_id] ?? {
                            cell_id: cell_id,
                            queued: true,
                            running: false,
                            errored: false,
                            runtime: null,
                            output: null,
                            logs: [],
                        }}
                        cell_input=${notebook.cell_inputs[cell_id]}
                        cell_input_local=${cell_inputs_local[cell_id]}
                        notebook_id=${notebook.notebook_id}
                        on_update_doc_query=${on_update_doc_query}
                        on_cell_input=${on_cell_input}
                        on_focus_neighbor=${on_focus_neighbor}
                        selected=${selected_cells.includes(cell_id)}
                        selected_cells=${selected_cells}
                        focus_after_creation=${last_created_cell === cell_id}
                        force_hide_input=${cell_inputs_delayed && i > render_cell_inputs_minimum}
                        is_process_ready=${is_process_ready}
                        disable_input=${disable_input}
                    />`
                )}
        </pluto-notebook>
    `
}
/* Disable this until we understand Notebook memoization better
export const NotebookMemo = ({
    is_initializing,
    notebook,
    cell_inputs_local,
    on_update_doc_query,
    on_cell_input,
    on_focus_neighbor,
    disable_input,
    last_created_cell,
    selected_cells,
}) => {
    return useMemo(() => {
        return html`
            <${Notebook}
                is_initializing=${is_initializing}
                notebook=${notebook}
                cell_inputs_local=${cell_inputs_local}
                on_update_doc_query=${on_update_doc_query}
                on_cell_input=${on_cell_input}
                on_focus_neighbor=${on_focus_neighbor}
                disable_input=${disable_input}
                last_created_cell=${last_created_cell}
                selected_cells=${selected_cells}
            />
        `
    }, [is_initializing, notebook, cell_inputs_local, on_update_doc_query, on_cell_input, on_focus_neighbor, disable_input, last_created_cell, selected_cells])
}
*/
export const NotebookMemo = Notebook
