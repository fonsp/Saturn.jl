import { html, Component, useState, useEffect, useMemo } from "../imports/Preact.js"
import immer, { applyPatches, produceWithPatches } from "../imports/immer.js"
import _ from "../imports/lodash.js"

import { create_pluto_connection, resolvable_promise } from "../common/PlutoConnection.js"
import { create_counter_statistics, send_statistics_if_enabled, store_statistics_sample, finalize_statistics, init_feedback } from "../common/Feedback.js"

import { FilePicker } from "./FilePicker.js"
import { NotebookMemo as Notebook } from "./Notebook.js"
import { LiveDocs } from "./LiveDocs.js"
import { DropRuler } from "./DropRuler.js"
import { SelectionArea } from "./SelectionArea.js"
import { UndoDelete } from "./UndoDelete.js"
import { SlideControls } from "./SlideControls.js"
import { Scroller } from "./Scroller.js"
import { ExportBanner } from "./ExportBanner.js"
import { ProgressBar } from "./ProgressBar.js"

import { slice_utf8, length_utf8 } from "../common/UnicodeTools.js"
import { has_ctrl_or_cmd_pressed, ctrl_or_cmd_name, is_mac_keyboard, in_textarea_or_input } from "../common/KeyboardShortcuts.js"
import { handle_log } from "../common/Logging.js"
import { PlutoContext, PlutoBondsContext } from "../common/PlutoContext.js"
import { useDropHandler } from "./useDropHandler.js"

const default_path = "..."
const DEBUG_DIFFING = false
let pending_local_updates = 0
// from our friends at https://stackoverflow.com/a/2117523
// i checked it and it generates Julia-legal UUIDs and that's all we need -SNOF
const uuidv4 = () =>
    //@ts-ignore
    "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (c) => (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16))

/**
 * @typedef {import('../imports/immer').Patch} Patch
 * */

/**
 * Serialize an array of cells into a string form (similar to the .jl file).
 *
 * Used for implementing clipboard functionality. This isn't in topological
 * order, so you won't necessarily be able to run it directly.
 *
 * @param {Array<CellInputData>} cells
 * @return {String}
 */
function serialize_cells(cells) {
    return cells.map((cell) => `# ╔═╡ ${cell.cell_id}\n` + cell.code + "\n").join("\n")
}

/**
 * Deserialize a Julia program or output from `serialize_cells`.
 *
 * If a Julia program, it will return a single String containing it. Otherwise,
 * it will split the string into cells based on the special delimiter.
 *
 * @param {String} serialized_cells
 * @return {Array<String>}
 */
function deserialize_cells(serialized_cells) {
    const segments = serialized_cells.replace(/\r\n/g, "\n").split(/# ╔═╡ \S+\n/)
    return segments.map((s) => s.trim()).filter((s) => s !== "")
}

const Main = ({ children }) => {
    const { handler } = useDropHandler()
    useEffect(() => {
        document.body.addEventListener("drop", handler)
        document.body.addEventListener("dragover", handler)
        document.body.addEventListener("dragenter", handler)
        document.body.addEventListener("dragleave", handler)
        return () => {
            document.body.removeEventListener("drop", handler)
            document.body.removeEventListener("dragover", handler)
            document.body.removeEventListener("dragenter", handler)
            document.body.removeEventListener("dragleave", handler)
        }
    })
    return html`<main>${children}</main>`
}

/**
 * @typedef CellInputData
 * @type {{
 *  cell_id: string,
 *  code: string,
 *  code_folded: boolean,
 * }}
 */

/**
 * @typedef CellResultData
 * @type {{
 *  cell_id: string,
 *  queued: boolean,
 *  running: boolean,
 *  errored: boolean,
 *  runtime?: number,
 *  output: {
 *      body: string,
 *      persist_js_state: boolean,
 *      last_run_timestamp: number,
 *      mime: string,
 *      rootassignee: ?string,
 *  }
 * }}
 */

/**
 * @typedef NotebookData
 * @type {{
 *  path: string,
 *  shortpath: string,
 *  in_temp_dir: boolean,
 *  notebook_id: string,
 *  cell_inputs: { [uuid: string]: CellInputData },
 *  cell_results: { [uuid: string]: CellResultData }
 *  cell_order: Array<string>,
 *  bonds: { [name: string]: any },
 * }}
 */

export class Editor extends Component {
    constructor() {
        super()

        this.state = {
            notebook: /** @type {NotebookData} */ ({
                notebook_id: new URLSearchParams(window.location.search).get("id"),
                path: default_path,
                shortpath: "",
                in_temp_dir: true,
                cell_inputs: {},
                cell_results: {},
                cell_order: [],
            }),
            cell_inputs_local: /** @type {{ [id: string]: CellInputData }} */ ({}),
            desired_doc_query: null,
            recently_deleted: /** @type {Array<{ index: number, cell: CellInputData }>} */ (null),
            connected: false,
            initializing: true,
            moving_file: false,
            scroller: {
                up: false,
                down: false,
            },
            export_menu_open: false,

            last_created_cell: null,
            selected_cells: [],

            update_is_ongoing: false,
        }

        // statistics that are accumulated over time
        this.counter_statistics = create_counter_statistics()

        // these are things that can be done to the local notebook
        this.actions = {
            send: (...args) => this.client.send(...args),
            update_notebook: (...args) => this.update_notebook(...args),
            set_doc_query: (query) => this.setState({ desired_doc_query: query }),
            set_local_cell: (cell_id, new_val, callback) => {
                return this.setState(
                    immer((state) => {
                        state.cell_inputs_local[cell_id] = {
                            code: new_val,
                        }
                        state.selected_cells = []
                    }),
                    callback
                )
            },
            focus_on_neighbor: (cell_id, delta, line = delta === -1 ? Infinity : -1, ch) => {
                const i = this.state.notebook.cell_order.indexOf(cell_id)
                const new_i = i + delta
                if (new_i >= 0 && new_i < this.state.notebook.cell_order.length) {
                    window.dispatchEvent(
                        new CustomEvent("cell_focus", {
                            detail: {
                                cell_id: this.state.notebook.cell_order[new_i],
                                line: line,
                                ch: ch,
                            },
                        })
                    )
                }
            },
            add_deserialized_cells: async (data, index) => {
                let new_codes = deserialize_cells(data)
                /** @type {Array<CellInputData>} */
                /** Create copies of the cells with fresh ids */
                let new_cells = new_codes.map((code) => ({
                    cell_id: uuidv4(),
                    code: code,
                    code_folded: false,
                }))
                if (index === -1) {
                    index = this.state.notebook.cell_order.length
                }

                /** Update local_code. Local code doesn't force CM to update it's state
                 * (the usual flow is keyboard event -> cm -> local_code and not the opposite )
                 * See ** 1 **
                 */
                await new Promise((resolve) =>
                    this.setState(
                        immer((state) => {
                            for (let cell of new_cells) {
                                state.cell_inputs_local[cell.cell_id] = cell
                            }
                            state.last_created_cell = new_cells[0]?.cell_id
                        }),
                        resolve
                    )
                )

                /**
                 * Create an empty cell in the julia-side.
                 * Code will differ, until the user clicks 'run' on the new code
                 */
                await update_notebook((notebook) => {
                    for (const cell of new_cells) {
                        notebook.cell_inputs[cell.cell_id] = {
                            ...cell,
                            // Fill the cell with empty code remotely, so it doesn't run unsafe code
                            code: "",
                        }
                    }
                    notebook.cell_order = [
                        ...notebook.cell_order.slice(0, index),
                        ...new_cells.map((x) => x.cell_id),
                        ...notebook.cell_order.slice(index, Infinity),
                    ]
                })
                /** ** 1 **
                 * Notify codemirrors that the code is updated
                 *
                 *  */

                for (const cell of new_cells) {
                    const cm = document.querySelector(`[id="${cell.cell_id}"] .CodeMirror`).CodeMirror
                    cm.setValue(cell.code) // Update codemirror synchronously
                }
            },
            wrap_remote_cell: async (cell_id, block_start = "begin", block_end = "end") => {
                const cell = this.state.notebook.cell_inputs[cell_id]
                const new_code = `${block_start}\n\t${cell.code.replace(/\n/g, "\n\t")}\n${block_end}`
                await new Promise((resolve) => {
                    this.setState(
                        immer((state) => {
                            state.cell_inputs_local[cell_id] = {
                                ...cell,
                                ...state.cell_inputs_local[cell_id],
                                code: new_code,
                            }
                        }),
                        resolve
                    )
                })
                await this.actions.set_and_run_multiple([cell_id])
            },
            split_remote_cell: async (cell_id, boundaries, submit = false) => {
                const cell = this.state.notebook.cell_inputs[cell_id]

                const old_code = cell.code
                const padded_boundaries = [0, ...boundaries]
                /** @type {Array<String>} */
                const parts = boundaries.map((b, i) => slice_utf8(old_code, padded_boundaries[i], b).trim()).filter((x) => x !== "")
                /** @type {Array<CellInputData>} */
                const cells_to_add = parts.map((code) => {
                    return {
                        cell_id: uuidv4(),
                        code: code,
                        code_folded: false,
                    }
                })

                this.setState(
                    immer((state) => {
                        for (let cell of cells_to_add) {
                            state.cell_inputs_local[cell.cell_id] = cell
                        }
                    })
                )
                await update_notebook((notebook) => {
                    // delete the old cell
                    delete notebook.cell_inputs[cell_id]

                    // add the new ones
                    for (let cell of cells_to_add) {
                        notebook.cell_inputs[cell.cell_id] = cell
                    }
                    notebook.cell_order = notebook.cell_order.flatMap((c) => {
                        if (cell_id === c) {
                            return cells_to_add.map((x) => x.cell_id)
                        } else {
                            return [c]
                        }
                    })
                })

                if (submit) {
                    await this.actions.set_and_run_multiple(cells_to_add.map((x) => x.cell_id))
                }
            },
            interrupt_remote: (cell_id) => {
                // TODO Make this cooler
                // set_notebook_state((prevstate) => {
                //     return {
                //         cells: prevstate.cells.map((c) => {
                //             return { ...c, errored: c.errored || c.running || c.queued }
                //         }),
                //     }
                // })
                this.client.send("interrupt_all", {}, { notebook_id: this.state.notebook.notebook_id }, false)
            },
            move_remote_cells: (cell_ids, new_index) => {
                update_notebook((notebook) => {
                    let before = notebook.cell_order.slice(0, new_index).filter((x) => !cell_ids.includes(x))
                    let after = notebook.cell_order.slice(new_index, Infinity).filter((x) => !cell_ids.includes(x))
                    notebook.cell_order = [...before, ...cell_ids, ...after]
                })
            },
            add_remote_cell_at: async (index, code = "") => {
                let id = uuidv4()
                this.setState({ last_created_cell: id })
                await update_notebook((notebook) => {
                    notebook.cell_inputs[id] = {
                        cell_id: id,
                        code,
                        code_folded: false,
                    }
                    notebook.cell_order = [...notebook.cell_order.slice(0, index), id, ...notebook.cell_order.slice(index, Infinity)]
                })
                await this.client.send("run_multiple_cells", { cells: [id] }, { notebook_id: this.state.notebook.notebook_id })
                return id
            },
            add_remote_cell: async (cell_id, before_or_after, code) => {
                const index = this.state.notebook.cell_order.indexOf(cell_id)
                const delta = before_or_after == "before" ? 0 : 1
                return await this.actions.add_remote_cell_at(index + delta, code)
            },
            confirm_delete_multiple: async (verb, cell_ids) => {
                if (cell_ids.length <= 1 || confirm(`${verb} ${cell_ids.length} cells?`)) {
                    if (cell_ids.some((cell_id) => this.state.notebook.cell_results[cell_id].running || this.state.notebook.cell_results[cell_id].queued)) {
                        if (confirm("This cell is still running - would you like to interrupt the notebook?")) {
                            this.actions.interrupt_remote(cell_ids[0])
                        }
                    } else {
                        this.setState({
                            recently_deleted: cell_ids.map((cell_id) => {
                                return {
                                    index: this.state.notebook.cell_order.indexOf(cell_id),
                                    cell: this.state.notebook.cell_inputs[cell_id],
                                }
                            }),
                        })
                        await update_notebook((notebook) => {
                            for (let cell_id of cell_ids) {
                                delete notebook.cell_inputs[cell_id]
                            }
                            notebook.cell_order = notebook.cell_order.filter((cell_id) => !cell_ids.includes(cell_id))
                        })
                        await this.client.send("run_multiple_cells", { cells: [] }, { notebook_id: this.state.notebook.notebook_id })
                    }
                }
            },
            fold_remote_cell: async (cell_id, newFolded) => {
                if (!newFolded) {
                    this.setState({ last_created_cell: cell_id })
                }
                await update_notebook((notebook) => {
                    notebook.cell_inputs[cell_id].code_folded = newFolded
                })
            },
            set_and_run_all_changed_remote_cells: () => {
                const changed = this.state.notebook.cell_order.filter(
                    (cell_id) =>
                        this.state.cell_inputs_local[cell_id] != null &&
                        this.state.notebook.cell_inputs[cell_id].code !== this.state.cell_inputs_local[cell_id]?.code
                )
                this.actions.set_and_run_multiple(changed)
                return changed.length > 0
            },
            set_and_run_multiple: async (cell_ids) => {
                // TODO: this function is called with an empty list sometimes, where?
                if (cell_ids.length > 0) {
                    this.counter_statistics.numEvals++
                    await update_notebook((notebook) => {
                        for (let cell_id of cell_ids) {
                            if (this.state.cell_inputs_local[cell_id]) {
                                notebook.cell_inputs[cell_id].code = this.state.cell_inputs_local[cell_id].code
                            }
                        }
                    })
                    // This is a "dirty" trick, as this should actually be stored in some shared request_status => status state
                    // But for now... this is fine 😼
                    this.setState(
                        immer((state) => {
                            for (let cell_id of cell_ids) {
                                if (state.notebook.cell_results[cell_id]) {
                                    state.notebook.cell_results[cell_id].queued = true
                                } else {
                                    // nothing
                                }
                            }
                        })
                    )
                    await this.client.send("run_multiple_cells", { cells: cell_ids }, { notebook_id: this.state.notebook.notebook_id })
                }
            },
            set_bond: async (symbol, value, is_first_value) => {
                // For now I discard is_first_value, basing it on if there
                // is a value already present in the state.
                // Keep an eye on https://github.com/fonsp/Pluto.jl/issues/275

                this.counter_statistics.numBondSets++

                // Wrap the bond value in an object so immer assumes it is changed
                await update_notebook((notebook) => {
                    notebook.bonds[symbol] = { value: value }
                })
            },
            reshow_cell: (cell_id, objectid, dim) => {
                this.client.send(
                    "reshow_cell",
                    {
                        objectid: objectid,
                        dim: dim,
                        cell_id: cell_id,
                    },
                    { notebook_id: this.state.notebook.notebook_id },
                    false
                )
            },
            write_file: (cell_id, { file, name, type }) => {
                this.counter_statistics.numFileDrops++
                return this.client.send(
                    "write_file",
                    { file, name, type, path: this.state.notebook.path },
                    {
                        notebook_id: this.state.notebook.notebook_id,
                        cell_id: cell_id,
                    },
                    true
                )
            },
        }

        // these are update message that are _not_ a response to a `send(*, *, {create_promise: true})`
        const on_update = (update, by_me) => {
            if (this.state.notebook.notebook_id === update.notebook_id) {
                const message = update.message
                switch (update.type) {
                    case "notebook_diff":
                        if (message.patches.length !== 0) {
                            this.setState(
                                immer((state) => {
                                    let new_notebook = applyPatches(state.notebook, message.patches)

                                    if (DEBUG_DIFFING) {
                                        console.group("Update!")
                                        for (let patch of message.patches) {
                                            console.group(`Patch :${patch.op}`)
                                            console.log(patch.path)
                                            console.log(patch.value)
                                            console.groupEnd()
                                        }
                                        console.groupEnd()
                                    }

                                    let cells_stuck_in_limbo = new_notebook.cell_order.filter((cell_id) => new_notebook.cell_inputs[cell_id] == null)
                                    if (cells_stuck_in_limbo.length !== 0) {
                                        console.warn(`cells_stuck_in_limbo:`, cells_stuck_in_limbo)
                                        new_notebook.cell_order = new_notebook.cell_order.filter((cell_id) => new_notebook.cell_inputs[cell_id] != null)
                                    }
                                    state.notebook = new_notebook
                                })
                            )
                        }
                        break
                    case "log":
                        handle_log(message, this.state.notebook.path)
                        break
                    default:
                        console.error("Received unknown update type!", update)
                        // alert("Something went wrong 🙈\n Try clearing your browser cache and refreshing the page")
                        break
                }
            } else {
                // Update for a different notebook, TODO maybe log this as it shouldn't happen
            }
        }

        const on_establish_connection = async (client) => {
            // nasty
            Object.assign(this.client, client)

            // @ts-ignore
            window.version_info = this.client.version_info // for debugging

            await this.client.send("update_notebook", { updates: [] }, { notebook_id: this.state.notebook.notebook_id }, false)

            this.setState({ initializing: false })

            // do one autocomplete to trigger its precompilation
            // TODO Do this from julia itself
            await this.client.send("complete", { query: "sq" }, { notebook_id: this.state.notebook.notebook_id })

            setTimeout(() => {
                init_feedback()
                finalize_statistics(this.state, this.client, this.counter_statistics).then(store_statistics_sample)

                setInterval(() => {
                    finalize_statistics(this.state, this.client, this.counter_statistics).then((statistics) => {
                        store_statistics_sample(statistics)
                        send_statistics_if_enabled(statistics)
                    })
                    this.counter_statistics = create_counter_statistics()
                }, 10 * 60 * 1000) // 10 minutes - statistics interval
            }, 5 * 1000) // 5 seconds - load feedback a little later for snappier UI
        }

        const on_connection_status = (val) => this.setState({ connected: val })

        const on_reconnect = () => {
            console.warn("Reconnected! Checking states")

            return true
        }

        this.client = {}
        create_pluto_connection({
            on_unrequested_update: on_update,
            on_connection_status: on_connection_status,
            on_reconnect: on_reconnect,
            connect_metadata: { notebook_id: this.state.notebook.notebook_id },
        }).then(on_establish_connection)

        // Not completely happy with this yet, but it will do for now - DRAL
        this.bonds_changes_to_apply_when_done = []
        this.notebook_is_idle = () =>
            !Object.values(this.state.notebook.cell_results).some((cell) => cell.running || cell.queued) && !this.state.update_is_ongoing

        console.log("asdf")
        /** @param {(notebook: NotebookData) => void} mutate_fn */
        let update_notebook = async (mutate_fn) => {
            // if (this.state.initializing) {
            //     console.error("Update notebook done during initializing, strange")
            //     return
            // }

            let [new_notebook, changes, inverseChanges] = produceWithPatches(this.state.notebook, (notebook) => {
                mutate_fn(notebook)
            })

            // If "notebook is not idle" I seperate and store the bonds updates,
            // to send when the notebook is idle. This delays the updating of the bond for performance,
            // but when the server can discard bond updates itself (now it executes them one by one, even if there is a newer update ready)
            // this will no longer be necessary
            if (!this.notebook_is_idle()) {
                let changes_involving_bonds = changes.filter((x) => x.path[0] === "bonds")
                this.bonds_changes_to_apply_when_done = [...this.bonds_changes_to_apply_when_done, ...changes_involving_bonds]
                changes = changes.filter((x) => x.path[0] !== "bonds")
            }

            if (DEBUG_DIFFING) {
                try {
                    let previous_function_name = new Error().stack.split("\n")[2].trim().split(" ")[1]
                    console.log(`Changes to send to server from "${previous_function_name}":`, changes)
                } catch (error) {}
            }
            if (changes.length === 0) {
                return
            }

            for (let change of changes) {
                if (change.path.some((x) => typeof x === "number")) {
                    throw new Error("This sounds like it is editting an array!!!")
                }
            }
            pending_local_updates++
            this.setState({ update_is_ongoing: pending_local_updates > 0 })
            try {
                await Promise.all([
                    this.client.send("update_notebook", { updates: changes }, { notebook_id: this.state.notebook.notebook_id }, false).then((response) => {
                        if (response.message.response.update_went_well === "👎") {
                            // We only throw an error for functions that are waiting for this
                            // Notebook state will already have the changes reversed
                            throw new Error(`Pluto update_notebook error: ${response.message.response.why_not})`)
                        }
                    }),
                    new Promise((resolve) => {
                        this.setState(
                            {
                                notebook: new_notebook,
                            },
                            resolve
                        )
                    }),
                ])
            } finally {
                pending_local_updates--
                this.setState({ update_is_ongoing: pending_local_updates > 0 })
            }
        }
        this.update_notebook = update_notebook

        this.submit_file_change = async (new_path, reset_cm_value) => {
            const old_path = this.state.notebook.path
            if (old_path === new_path) {
                return
            }
            if (!this.state.notebook.in_temp_dir) {
                if (!confirm("Are you sure? Will move from\n\n" + old_path + "\n\nto\n\n" + new_path)) {
                    throw new Error("Declined by user")
                }
            }

            this.setState({ moving_file: true })

            try {
                await update_notebook((notebook) => {
                    notebook.in_temp_dir = false
                    notebook.path = new_path
                })
                // @ts-ignore
                document.activeElement?.blur()
            } catch (error) {
                alert("Failed to move file:\n\n" + error.message)
            } finally {
                this.setState({ moving_file: false })
            }
        }

        this.delete_selected = (verb) => {
            if (this.state.selected_cells.length > 0) {
                this.actions.confirm_delete_multiple(verb, this.state.selected_cells)
                return true
            }
        }

        this.run_selected = () => {
            return this.actions.set_and_run_multiple(this.state.selected_cells)
        }

        this.serialize_selected = (cell_id = null) => {
            const cells_to_serialize = cell_id == null || this.state.selected_cells.includes(cell_id) ? this.state.selected_cells : [cell_id]
            if (cells_to_serialize.length) {
                return serialize_cells(cells_to_serialize.map((id) => this.state.notebook.cell_inputs[id]))
            }
        }

        document.addEventListener("keydown", (e) => {
            // if (e.defaultPrevented) {
            //     return
            // }
            if (e.key === "q" && has_ctrl_or_cmd_pressed(e)) {
                // This one can't be done as cmd+q on mac, because that closes chrome - Dral
                if (Object.values(this.state.notebook.cell_results).some((c) => c.running || c.queued)) {
                    this.actions.interrupt_remote()
                }
                e.preventDefault()
            } else if (e.key === "s" && has_ctrl_or_cmd_pressed(e)) {
                const some_cells_ran = this.actions.set_and_run_all_changed_remote_cells()
                if (!some_cells_ran) {
                    // all cells were in sync allready
                    // TODO: let user know that the notebook autosaves
                }
                e.preventDefault()
            } else if (e.key === "Backspace" || e.key === "Delete") {
                if (this.delete_selected("Delete")) {
                    e.preventDefault()
                }
            } else if (e.key === "Enter" && e.shiftKey) {
                this.run_selected()
            } else if ((e.key === "?" && has_ctrl_or_cmd_pressed(e)) || e.key === "F1") {
                // On mac "cmd+shift+?" is used by chrome, so that is why this needs to be ctrl as well on mac
                // Also pressing "ctrl+shift" on mac causes the key to show up as "/", this madness
                // I hope we can find a better solution for this later - Dral
                alert(
                    `Shortcuts 🎹

    Shift+Enter:   run cell
    ${ctrl_or_cmd_name}+Enter:   run cell and add cell below
    Delete or Backspace:   delete empty cell

    PageUp or fn+Up:   select cell above
    PageDown or fn+Down:   select cell below

    ${ctrl_or_cmd_name}+Q:   interrupt notebook
    ${ctrl_or_cmd_name}+S:   submit all changes

    ${ctrl_or_cmd_name}+C:   copy selected cells
    ${ctrl_or_cmd_name}+X:   cut selected cells
    ${ctrl_or_cmd_name}+V:   paste selected cells

    The notebook file saves every time you run`
                )
                e.preventDefault()
            }
        })

        document.addEventListener("copy", (e) => {
            if (!in_textarea_or_input()) {
                const serialized = this.serialize_selected()
                if (serialized) {
                    navigator.clipboard.writeText(serialized).catch((err) => {
                        alert(`Error copying cells: ${e}`)
                    })
                }
            }
        })

        // Disabled because we don't want to accidentally delete cells
        // or we can enable it with a prompt
        // Even better would be excel style: grey out until you paste it. If you paste within the same notebook, then it is just a move.
        // document.addEventListener("cut", (e) => {
        //     if (!in_textarea_or_input()) {
        //         const serialized = this.serialize_selected()
        //         if (serialized) {
        //             navigator.clipboard
        //                 .writeText(serialized)
        //                 .then(() => this.delete_selected("Cut"))
        //                 .catch((err) => {
        //                     alert(`Error cutting cells: ${e}`)
        //                 })
        //         }
        //     }
        // })

        document.addEventListener("paste", async (e) => {
            const topaste = e.clipboardData.getData("text/plain")
            if (!in_textarea_or_input() || topaste.match(/# ╔═╡ ........-....-....-....-............/g)?.length) {
                // Deselect everything first, to clean things up
                this.setState({
                    selected_cells: [],
                })

                // Paste in the cells at the end of the notebook
                const data = e.clipboardData.getData("text/plain")
                this.actions.add_deserialized_cells(data, -1)
                e.preventDefault()
            }
        })

        window.addEventListener("beforeunload", (event) => {
            const unsaved_cells = this.state.notebook.cell_order.filter(
                (id) => this.state.cell_inputs_local[id] && this.state.notebook.cell_inputs[id].code !== this.state.cell_inputs_local[id].code
            )
            const first_unsaved = unsaved_cells[0]
            if (first_unsaved != null) {
                window.dispatchEvent(new CustomEvent("cell_focus", { detail: { cell_id: first_unsaved } }))
                // } else if (this.state.notebook.in_temp_dir) {
                //     window.scrollTo(0, 0)
                //     // TODO: focus file picker
                console.log("Preventing unload")
                event.stopImmediatePropagation()
                event.preventDefault()
                event.returnValue = ""
            } else {
                console.warn("unloading 👉 disconnecting websocket")
                // and don't prevent the unload
            }
        })
    }

    componentDidUpdate(old_props, old_state) {
        window.editor_state = this.state
        document.title = "🎈 " + this.state.notebook.shortpath + " ⚡ Pluto.jl ⚡"

        if (old_state?.notebook?.path !== this.state.notebook.path) {
            update_stored_recent_notebooks(this.state.notebook.path, old_state?.notebook?.path)
        }

        const any_code_differs = this.state.notebook.cell_order.some(
            (cell_id) =>
                this.state.cell_inputs_local[cell_id] != null && this.state.notebook.cell_inputs[cell_id].code !== this.state.cell_inputs_local[cell_id].code
        )
        document.body.classList.toggle("code_differs", any_code_differs)
        // this class is used to tell our frontend tests that the updates are done
        document.body.classList.toggle("update_is_ongoing", pending_local_updates > 0)
        document.body.classList.toggle("loading", this.state.initializing || this.state.moving_file)
        if (this.state.connected) {
            // @ts-ignore
            document.querySelector("meta[name=theme-color]").content = "#fff"
            document.body.classList.remove("disconnected")
        } else {
            // @ts-ignore
            document.querySelector("meta[name=theme-color]").content = "#DEAF91"
            document.body.classList.add("disconnected")
        }

        if (this.notebook_is_idle() && this.bonds_changes_to_apply_when_done.length !== 0) {
            let bonds_patches = this.bonds_changes_to_apply_when_done
            this.bonds_changes_to_apply_when_done = []
            this.update_notebook((notebook) => {
                applyPatches(notebook, bonds_patches)
            })
        }
    }

    render() {
        let { export_menu_open } = this.state

        return html`
            <${PlutoContext.Provider} value=${this.actions}>
                <${PlutoBondsContext.Provider} value=${this.state.notebook.bonds}>
                    <${Scroller} active=${this.state.scroller} />
                    <${ProgressBar} notebook=${this.state.notebook}/>
                    <header className=${export_menu_open ? "show_export" : ""}>
                        <${ExportBanner}
                            pluto_version=${this.client?.version_info?.pluto}
                            notebook=${this.state.notebook}
                            open=${export_menu_open}
                            onClose=${() => this.setState({ export_menu_open: false })}
                        />
                        <nav id="at_the_top">
                            <a href="./">
                                <h1><img id="logo-big" src="img/logo.svg" alt="Pluto.jl" /><img id="logo-small" src="img/favicon_unsaturated.svg" /></h1>
                            </a>
                            <${FilePicker}
                                client=${this.client}
                                value=${this.state.notebook.in_temp_dir ? "" : this.state.notebook.path}
                                on_submit=${this.submit_file_change}
                                suggest_new_file=${{
                                    base: this.client.session_options == null ? "" : this.client.session_options.server.notebook_path_suggestion,
                                    name: this.state.notebook.shortpath,
                                }}
                                placeholder="Save notebook..."
                                button_label=${this.state.notebook.in_temp_dir ? "Choose" : "Move"}
                            />
                            <button class="toggle_export" title="Export..." onClick=${() => this.setState({ export_menu_open: !export_menu_open })}>
                                <span></span>
                            </button>
                        </nav>
                    </header>
                    <${Main}>
                        <preamble>
                            <button
                                onClick=${() => {
                                    this.actions.set_and_run_all_changed_remote_cells()
                                }}
                                class="runallchanged"
                                title="Save and run all changed cells"
                            >
                                <span></span>
                            </button>
                        </preamble>
                        <${Notebook}
                            is_initializing=${this.state.initializing}
                            notebook=${this.state.notebook}
                            selected_cells=${this.state.selected_cells}
                            cell_inputs_local=${this.state.cell_inputs_local}
                            on_update_doc_query=${this.actions.set_doc_query}
                            on_cell_input=${this.actions.set_local_cell}
                            on_focus_neighbor=${this.actions.focus_on_neighbor}
                            disable_input=${!this.state.connected}
                            last_created_cell=${this.state.last_created_cell}
                        />

                        <${DropRuler} 
                            actions=${this.actions}
                            selected_cells=${this.state.selected_cells} 
                            set_scroller=${(enabled) => {
                                this.setState({ scroller: enabled })
                            }} 
                            serialize_selected=${this.serialize_selected}
                        />

                        <${SelectionArea}
                            actions=${this.actions}
                            cell_order=${this.state.notebook.cell_order}
                            selected_cell_ids=${this.state.selected_cell_ids}
                            set_scroller=${(enabled) => {
                                this.setState({ scroller: enabled })
                            }}
                            on_selection=${(selected_cell_ids) => {
                                // @ts-ignore
                                if (
                                    selected_cell_ids.length !== this.state.selected_cells ||
                                    _.difference(selected_cell_ids, this.state.selected_cells).length !== 0
                                ) {
                                    this.setState({
                                        selected_cells: selected_cell_ids,
                                    })
                                }
                            }}
                        />
                    </${Main}>
                    <${LiveDocs}
                        desired_doc_query=${this.state.desired_doc_query}
                        on_update_doc_query=${this.actions.set_doc_query}
                        notebook=${this.state.notebook}
                    />
                    <${UndoDelete}
                        recently_deleted=${this.state.recently_deleted}
                        on_click=${() => {
                            this.update_notebook((notebook) => {
                                for (let { index, cell } of this.state.recently_deleted) {
                                    notebook.cell_inputs[cell.cell_id] = cell
                                    notebook.cell_order = [...notebook.cell_order.slice(0, index), cell.cell_id, ...notebook.cell_order.slice(index, Infinity)]
                                }
                            }).then(() => {
                                this.actions.set_and_run_multiple(this.state.recently_deleted.map(({ cell }) => cell.cell_id))
                            })
                        }}
                    />
                    <${SlideControls} />
                    <footer>
                        <div id="info">
                            <form id="feedback" action="#" method="post">
                                <a href="statistics-info">Statistics</a>
                                <a href="https://github.com/fonsp/Pluto.jl/wiki">FAQ</a>
                                <span style="flex: 1"></span>
                                <label for="opinion">🙋 How can we make <a href="https://github.com/fonsp/Pluto.jl">Pluto.jl</a> better?</label>
                                <input type="text" name="opinion" id="opinion" autocomplete="off" placeholder="Instant feedback..." />
                                <button>Send</button>
                            </form>
                        </div>
                    </footer>
                </${PlutoBondsContext.Provider}>
            </${PlutoContext.Provider}>
        `
    }
}

/* LOCALSTORAGE NOTEBOOKS LIST */

// TODO This is now stored locally, lets store it somewhere central 😈
export const update_stored_recent_notebooks = (recent_path, also_delete = undefined) => {
    const storedString = localStorage.getItem("recent notebooks")
    const storedList = storedString != null ? JSON.parse(storedString) : []
    const oldpaths = storedList
    const newpaths = [recent_path].concat(
        oldpaths.filter((path) => {
            return path !== recent_path && path !== also_delete
        })
    )
    localStorage.setItem("recent notebooks", JSON.stringify(newpaths.slice(0, 50)))
}
