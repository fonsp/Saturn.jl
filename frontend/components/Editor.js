import { html, Component, useState, useEffect, useMemo } from "../imports/Preact.js"
import immer, { applyPatches, produceWithPatches } from "../imports/immer.js"
import _ from "../imports/lodash.js"

import { create_pluto_connection } from "../common/PlutoConnection.js"
import { init_feedback } from "../common/Feedback.js"

import { FilePicker } from "./FilePicker.js"
import { Preamble } from "./Preamble.js"
import { NotebookMemo as Notebook } from "./Notebook.js"
import { LiveDocs } from "./LiveDocs.js"
import { DropRuler } from "./DropRuler.js"
import { SelectionArea } from "./SelectionArea.js"
import { UndoDelete } from "./UndoDelete.js"
import { SlideControls } from "./SlideControls.js"
import { Scroller } from "./Scroller.js"
import { FindReplace } from "./FindReplace.js"
import { ExportBanner } from "./ExportBanner.js"

import { slice_utf8, length_utf8 } from "../common/UnicodeTools.js"
import { has_ctrl_or_cmd_pressed, ctrl_or_cmd_name, is_mac_keyboard, in_textarea_or_input } from "../common/KeyboardShortcuts.js"
import { handle_log } from "../common/Logging.js"
import { PlutoContext, PlutoBondsContext } from "../common/PlutoContext.js"
import { unpack } from "../common/MsgPack.js"
import { useDropHandler } from "./useDropHandler.js"
import { start_binder, BinderPhase } from "../common/Binder.js"
import { read_Uint8Array_with_progress, FetchProgress } from "./FetchProgress.js"
import { BinderButton } from "./BinderButton.js"
import { slider_server_actions, nothing_actions } from "../common/SliderServerClient.js"

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

const ProcessStatus = {
    ready: "ready",
    starting: "starting",
    no_process: "no_process",
    waiting_to_restart: "waiting_to_restart",
}

/**
 * Map of status => Bool. In order of decreasing prioirty.
 */
const statusmap = (state) => ({
    disconnected: !(state.connected || state.initializing || state.static_preview),
    loading: (BinderPhase.wait_for_user < state.binder_phase && state.binder_phase < BinderPhase.ready) || state.initializing || state.moving_file,
    process_restarting: state.notebook.process_status === ProcessStatus.waiting_to_restart,
    process_dead: state.notebook.process_status === ProcessStatus.no_process || state.notebook.process_status === ProcessStatus.waiting_to_restart,
    static_preview: state.static_preview,
    binder: state.offer_binder || state.binder_phase != null,
    code_differs: state.notebook.cell_order.some(
        (cell_id) => state.cell_inputs_local[cell_id] != null && state.notebook.cell_inputs[cell_id].code !== state.cell_inputs_local[cell_id].code
    ),
})

const first_true_key = (obj) => {
    for (let [k, v] of Object.entries(obj)) {
        if (v) {
            return k
        }
    }
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
 *  published_objects: object,
 * }}
 */

/**
 * @typedef CellDependencyData
 * @type {{
 *  cell_id: string,
 *  downstream_cells_map: { [symbol: string]: Array<string>},
 *  upstream_cells_map: { [symbol: string]: Array<string>},
 *  precedence_heuristic: number,
 * }}
 */

/**
 * @typedef NotebookData
 * @type {{
 *  notebook_id: string,
 *  path: string,
 *  shortpath: string,
 *  in_temp_dir: boolean,
 *  process_status: string,
 *  cell_inputs: { [uuid: string]: CellInputData },
 *  cell_results: { [uuid: string]: CellResultData },
 *  cell_dependencies: { [uuid: string]: CellDependencyData },
 *  cell_order: Array<string>,
 *  cell_execution_order: Array<string>,
 *  bonds: { [name: string]: any },
 * }}
 */

const url_logo_big = document.head.querySelector("link[rel='pluto-logo-big']").getAttribute("href")
const url_logo_small = document.head.querySelector("link[rel='pluto-logo-small']").getAttribute("href")

/**
 *
 * @returns {NotebookData}
 */
const initial_notebook = () => ({
    notebook_id: new URLSearchParams(window.location.search).get("id"),
    path: default_path,
    shortpath: "",
    in_temp_dir: true,
    process_status: "starting",
    cell_inputs: {},
    cell_results: {},
    cell_dependencies: {},
    cell_order: [],
    cell_execution_order: [],
    bonds: {},
})

export class Editor extends Component {
    constructor() {
        super()

        const url_params = new URLSearchParams(window.location.search)
        this.launch_params = {
            //@ts-ignore
            statefile: url_params.get("statefile") ?? window.pluto_statefile,
            //@ts-ignore
            notebookfile: url_params.get("notebookfile") ?? window.pluto_notebookfile,
            //@ts-ignore
            disable_ui: !!(url_params.get("disable_ui") ?? window.pluto_disable_ui),
            //@ts-ignore
            binder_url: url_params.get("binder_url") ?? window.pluto_binder_url,
            //@ts-ignore
            slider_server_url: url_params.get("slider_server_url") ?? window.pluto_slider_server_url,
        }

        this.state = {
            notebook: /** @type {NotebookData} */ initial_notebook(),
            cell_inputs_local: /** @type {{ [id: string]: CellInputData }} */ ({}),
            desired_doc_query: null,
            recently_deleted: /** @type {Array<{ index: number, cell: CellInputData }>} */ (null),
            last_update_time: 0,

            disable_ui: this.launch_params.disable_ui,
            static_preview: this.launch_params.statefile != null,
            statefile_download_progress: null,
            offer_binder: this.launch_params.notebookfile != null && this.launch_params.binder_url != null,
            binder_phase: null,
            binder_session_url: null,
            binder_session_token: null,
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

        this.setStatePromise = (fn) => new Promise((r) => this.setState(fn, r))

        // these are things that can be done to the local notebook
        this.actions = {
            send: (...args) => this.client.send(...args),
            //@ts-ignore
            update_notebook: (...args) => this.update_notebook(...args),
            set_doc_query: (query) => this.setState({ desired_doc_query: query }),
            set_local_cell: (cell_id, new_val) => {
                return this.setStatePromise(
                    immer((state) => {
                        state.cell_inputs_local[cell_id] = {
                            code: new_val,
                        }
                        state.selected_cells = []
                    })
                )
            },
            focus_on_neighbor: (cell_id, delta, line = delta === -1 ? Infinity : -1, ch) => {
                const i = this.state.notebook.cell_order.indexOf(cell_id)
                const new_i = i + delta
                if (new_i >= 0 && new_i < this.state.notebook.cell_order.length) {
                    window.dispatchEvent(
                        new CustomEvent("cell_focus", {
                            detail: {
                                reason: "focus neighbor", // that's just documentation - page up/down!
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
                await this.setStatePromise(
                    immer((state) => {
                        for (let cell of new_cells) {
                            state.cell_inputs_local[cell.cell_id] = cell
                        }
                        state.last_created_cell = new_cells[0]?.cell_id
                    })
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
                    //@ts-ignore
                    const cm = document.querySelector(`[id="${cell.cell_id}"] .CodeMirror`).CodeMirror
                    cm.setValue(cell.code) // Update codemirror synchronously
                }
            },
            wrap_remote_cell: async (cell_id, block_start = "begin", block_end = "end") => {
                const cell = this.state.notebook.cell_inputs[cell_id]
                const new_code = `${block_start}\n\t${cell.code.replace(/\n/g, "\n\t")}\n${block_end}`

                await this.setStatePromise(
                    immer((state) => {
                        state.cell_inputs_local[cell_id] = {
                            ...cell,
                            ...state.cell_inputs_local[cell_id],
                            code: new_code,
                        }
                    })
                )
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
                            selected_cells: [],
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
                                    // state.notebook.cell_results[cell_id].queued = true
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

                await update_notebook((notebook) => {
                    // We wrap the bond value in an object so immer assumes it is changed
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

        const apply_notebook_patches = (patches, old_state = undefined) =>
            new Promise((resolve) => {
                if (patches.length !== 0) {
                    this.setState(
                        immer((state) => {
                            let new_notebook
                            try {
                                // To test this, uncomment the lines below:
                                // if (Math.random() < 0.25) {
                                //     throw new Error(`Error: [Immer] minified error nr: 15 '${patches?.[0]?.path?.join("/")}'    .`)
                                // }
                                new_notebook = applyPatches(old_state ?? state.notebook, patches)
                            } catch (exception) {
                                const failing_path = String(exception).match(".*'(.*)'.*")[1].replace(/\//gi, ".")
                                const path_value = _.get(this.state.notebook, failing_path, "Not Found")
                                console.log(String(exception).match(".*'(.*)'.*")[1].replace(/\//gi, "."), failing_path, typeof failing_path)
                                // The alert below is not catastrophic: the editor will try to recover.
                                // Deactivating to be user-friendly!
                                // alert(`Ooopsiee.`)
                                console.error(
                                    `#######################**************************########################
PlutoError: StateOutOfSync: Failed to apply patches.
Please report this: https://github.com/fonsp/Pluto.jl/issues adding the info below:
failing path: ${failing_path}
notebook previous value: ${path_value}
patch: ${JSON.stringify(
                                        patches?.find(({ path }) => path.join("") === failing_path),
                                        null,
                                        1
                                    )}
#######################**************************########################`,
                                    exception
                                )
                                console.log("Trying to recover: Refetching notebook...")
                                this.client.send(
                                    "reset_shared_state",
                                    {},
                                    {
                                        notebook_id: this.state.notebook.notebook_id,
                                    },
                                    false
                                )
                                return
                            }

                            if (DEBUG_DIFFING) {
                                console.group("Update!")
                                for (let patch of patches) {
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
                        }),
                        resolve
                    )
                } else {
                    resolve()
                }
            })

        // these are update message that are _not_ a response to a `send(*, *, {create_promise: true})`
        const on_update = (update, by_me) => {
            if (this.state.notebook.notebook_id === update.notebook_id) {
                const message = update.message
                switch (update.type) {
                    case "notebook_diff":
                        if (message?.response?.from_reset) {
                            console.log("Trying to reset state after failure")
                            try {
                                apply_notebook_patches(message.patches, initial_notebook())
                            } catch (exception) {
                                alert("Oopsie!! please refresh your browser and everything will be alright!")
                            }
                        } else if (message.patches.length !== 0) {
                            apply_notebook_patches(message.patches)
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

            this.setState({ initializing: false, static_preview: false, binder_phase: this.state.binder_phase == null ? null : BinderPhase.ready })

            // do one autocomplete to trigger its precompilation
            // TODO Do this from julia itself
            this.client.send("complete", { query: "sq" }, { notebook_id: this.state.notebook.notebook_id })

            setTimeout(init_feedback, 2 * 1000) // 2 seconds - load feedback a little later for snappier UI
        }

        const on_connection_status = (val) => this.setState({ connected: val })

        const on_reconnect = () => {
            console.warn("Reconnected! Checking states")

            return true
        }

        this.client = {}

        this.connect = (ws_address = undefined) =>
            create_pluto_connection({
                ws_address: ws_address,
                on_unrequested_update: on_update,
                on_connection_status: on_connection_status,
                on_reconnect: on_reconnect,
                connect_metadata: { notebook_id: this.state.notebook.notebook_id },
            }).then(on_establish_connection)

        this.real_actions = this.actions
        this.fake_actions =
            this.launch_params.slider_server_url != null
                ? slider_server_actions({
                      setStatePromise: this.setStatePromise,
                      actions: this.actions,
                      launch_params: this.launch_params,
                      apply_notebook_patches,
                      get_original_state: () => this.original_state,
                      get_current_state: () => this.state.notebook,
                  })
                : nothing_actions({
                      actions: this.actions,
                  })

        this.on_disable_ui = () => {
            document.body.classList.toggle("disable_ui", this.state.disable_ui)
            document.head.querySelector("link[data-pluto-file='hide-ui']").setAttribute("media", this.state.disable_ui ? "all" : "print")
            //@ts-ignore
            this.actions =
                this.state.disable_ui || (this.launch_params.slider_server_url != null && !this.state.connected) ? this.fake_actions : this.real_actions //heyo
        }
        this.on_disable_ui()

        this.original_state = null
        if (this.state.static_preview) {
            ;(async () => {
                const r = await fetch(this.launch_params.statefile)
                const data = await read_Uint8Array_with_progress(r, (progress) => {
                    this.setState({
                        statefile_download_progress: progress,
                    })
                })
                const state = unpack(data)
                this.original_state = state
                this.setState({
                    notebook: state,
                    initializing: false,
                    binder_phase: this.state.offer_binder ? BinderPhase.wait_for_user : null,
                })
            })()
            fetch(`https://cdn.jsdelivr.net/gh/fonsp/pluto-usage-counter@1/article-view.txt?skip_sw`).catch(() => {})
        } else {
            this.connect()
        }

        // Not completely happy with this yet, but it will do for now - DRAL
        this.bonds_changes_to_apply_when_done = []
        this.notebook_is_idle = () =>
            !Object.values(this.state.notebook.cell_results).some((cell) => cell.running || cell.queued) && !this.state.update_is_ongoing

        let last_update_notebook_task = Promise.resolve()
        /** @param {(notebook: NotebookData) => void} mutate_fn */
        let update_notebook = (mutate_fn) => {
            last_update_notebook_task = last_update_notebook_task
                .then(async () => {
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
                            throw new Error("This sounds like it is editing an array...")
                        }
                    }
                    pending_local_updates++
                    this.setState({ update_is_ongoing: pending_local_updates > 0 })
                    try {
                        await Promise.all([
                            this.client
                                .send("update_notebook", { updates: changes }, { notebook_id: this.state.notebook.notebook_id }, false)
                                .then((response) => {
                                    if (response.message.response.update_went_well === "👎") {
                                        // We only throw an error for functions that are waiting for this
                                        // Notebook state will already have the changes reversed
                                        throw new Error(`Pluto update_notebook error: ${response.message.response.why_not})`)
                                    }
                                }),
                            this.setStatePromise({
                                notebook: new_notebook,
                                last_update_time: Date.now(),
                            }),
                        ])
                    } finally {
                        pending_local_updates--
                        this.setState({ update_is_ongoing: pending_local_updates > 0 })
                    }
                })
                .catch(console.error)
            return last_update_notebook_task
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
            if (e.key.toLowerCase() === "q" && has_ctrl_or_cmd_pressed(e)) {
                // This one can't be done as cmd+q on mac, because that closes chrome - Dral
                if (Object.values(this.state.notebook.cell_results).some((c) => c.running || c.queued)) {
                    this.actions.interrupt_remote()
                }
                e.preventDefault()
            } else if (e.key.toLowerCase() === "s" && has_ctrl_or_cmd_pressed(e)) {
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

            if (this.state.disable_ui && this.state.offer_binder) {
                // const code = e.key.charCodeAt(0)
                if (e.key === "Enter" || e.key.length === 1) {
                    if (!document.body.classList.contains("wiggle_binder")) {
                        document.body.classList.add("wiggle_binder")
                        setTimeout(() => {
                            document.body.classList.remove("wiggle_binder")
                        }, 1000)
                    }
                }
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

        document.addEventListener("cut", (e) => {
            // Disabled because we don't want to accidentally delete cells
            // or we can enable it with a prompt
            // Even better would be excel style: grey out until you paste it. If you paste within the same notebook, then it is just a move.
            // if (!in_textarea_or_input()) {
            //     const serialized = this.serialize_selected()
            //     if (serialized) {
            //         navigator.clipboard
            //             .writeText(serialized)
            //             .then(() => this.delete_selected("Cut"))
            //             .catch((err) => {
            //                 alert(`Error cutting cells: ${e}`)
            //             })
            //     }
            // }
        })

        document.addEventListener("paste", async (e) => {
            const topaste = e.clipboardData.getData("text/plain")
            console.log("paste", topaste)
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
                //@ts-ignore
                if (window.shutdown_binder != null) {
                    // hmmmm that would also shut down the binder if you refreshed, or if you navigate to the binder session main menu by clicking the pluto logo.
                    // Let's keep it disabled for now and let the timeout take care of shutting down the binder
                    // window.shutdown_binder()
                }
                // and don't prevent the unload
            }
        })
    }

    componentDidUpdate(old_props, old_state) {
        //@ts-ignore
        window.editor_state = this.state

        const new_state = this.state

        if (old_state?.notebook?.path !== new_state.notebook.path) {
            update_stored_recent_notebooks(new_state.notebook.path, old_state?.notebook?.path)
        }
        if (old_state?.notebook?.shortpath !== new_state.notebook.shortpath) {
            document.title = "🎈 " + new_state.notebook.shortpath + " — Pluto.jl"
        }

        Object.entries(this.cached_status).forEach((e) => {
            document.body.classList.toggle(...e)
        })

        // this class is used to tell our frontend tests that the updates are done
        //@ts-ignore
        document.body._update_is_ongoing = pending_local_updates > 0

        if (this.notebook_is_idle() && this.bonds_changes_to_apply_when_done.length !== 0) {
            let bonds_patches = this.bonds_changes_to_apply_when_done
            this.bonds_changes_to_apply_when_done = []
            this.update_notebook((notebook) => {
                applyPatches(notebook, bonds_patches)
            })
        }

        if (old_state.binder_phase !== this.state.binder_phase && this.state.binder_phase != null) {
            const phase = Object.entries(BinderPhase).find(([k, v]) => v == this.state.binder_phase)[0]
            console.info(`Binder phase: ${phase} at ${new Date().toLocaleTimeString()}`)
        }

        if (old_state.disable_ui !== this.state.disable_ui) {
            this.on_disable_ui()
        }
    }

    componentWillUpdate(new_props, new_state) {
        this.cached_status = statusmap(new_state)
    }

    render() {
        let { export_menu_open, notebook } = this.state

        const status = this.cached_status ?? statusmap(this.state)
        const statusval = first_true_key(status)

        const export_url = (u) =>
            this.state.binder_session_url == null
                ? `./${u}?id=${this.state.notebook.notebook_id}`
                : `${this.state.binder_session_url}${u}?id=${this.state.notebook.notebook_id}&token=${this.state.binder_session_token}`

        return html`
            <${PlutoContext.Provider} value=${this.actions}>
                <${PlutoBondsContext.Provider} value=${this.state.notebook.bonds}>
                    <${Scroller} active=${this.state.scroller} />
                    <header className=${export_menu_open ? "show_export" : ""}>
                        <${ExportBanner}
                            notebookfile_url=${export_url("notebookfile")}
                            notebookexport_url=${export_url("notebookexport")}
                            open=${export_menu_open}
                            onClose=${() => this.setState({ export_menu_open: false })}
                        />
                        <loading-bar style=${`width: ${100 * this.state.binder_phase}vw`}></loading-bar>
                        ${
                            status.binder
                                ? html`<div id="binder_spinners">
                                      <binder-spinner id="ring_1"></binder-spinner>
                                      <binder-spinner id="ring_2"></binder-spinner>
                                      <binder-spinner id="ring_3"></binder-spinner>
                                  </div>`
                                : null
                        }
                        <nav id="at_the_top">
                            <a href=${
                                this.state.static_preview || this.state.binder_phase != null
                                    ? `${this.state.binder_session_url}?token=${this.state.binder_session_token}`
                                    : "./"
                            }>
                                <h1><img id="logo-big" src=${url_logo_big} alt="Pluto.jl" /><img id="logo-small" src=${url_logo_small} /></h1>
                            </a>
                            <div class="flex_grow_1"></div>
                            ${
                                this.state.binder_phase === BinderPhase.ready
                                    ? html`<pluto-filepicker><a href=${export_url("notebookfile")} target="_blank">Save notebook...</a></pluto-filepicker>`
                                    : html`<${FilePicker}
                                          client=${this.client}
                                          value=${notebook.in_temp_dir ? "" : notebook.path}
                                          on_submit=${this.submit_file_change}
                                          suggest_new_file=${{
                                              base: this.client.session_options == null ? "" : this.client.session_options.server.notebook_path_suggestion,
                                              name: notebook.shortpath,
                                          }}
                                          placeholder="Save notebook..."
                                          button_label=${notebook.in_temp_dir ? "Choose" : "Move"}
                                      />`
                            }
                            <div class="flex_grow_2"></div>
                            <button class="toggle_export" title="Export..." onClick=${() => {
                                this.setState({ export_menu_open: !export_menu_open })
                            }}><span></span></button>
                            <div id="process_status">${
                                status.binder && status.loading
                                    ? "Loading binder..."
                                    : statusval === "disconnected"
                                    ? "Reconnecting..."
                                    : statusval === "loading"
                                    ? "Loading..."
                                    : statusval === "process_restarting"
                                    ? "Process exited — restarting..."
                                    : statusval === "process_dead"
                                    ? html`${"Process exited — "}
                                          <a
                                              href="#"
                                              onClick=${() => {
                                                  this.client.send(
                                                      "restart_process",
                                                      {},
                                                      {
                                                          notebook_id: notebook.notebook_id,
                                                      }
                                                  )
                                              }}
                                              >restart</a
                                          >`
                                    : null
                            }</div>
                        </nav>
                    </header>
                    <${BinderButton} binder_phase=${this.state.binder_phase} start_binder=${() =>
            start_binder({ setStatePromise: this.setStatePromise, connect: this.connect, launch_params: this.launch_params })} notebookfile=${
            this.launch_params.notebookfile == null ? null : new URL(this.launch_params.notebookfile, window.location.href).href
        } />
                    <${FetchProgress} progress=${this.state.statefile_download_progress} />
                    <${Main}>
                        <${Preamble}
                            last_update_time=${this.state.last_update_time}
                            any_code_differs=${status.code_differs}
                        />
                        <${Notebook}
                            notebook=${this.state.notebook}
                            cell_inputs_local=${this.state.cell_inputs_local}
                            on_update_doc_query=${this.actions.set_doc_query}
                            on_cell_input=${this.actions.set_local_cell}
                            on_focus_neighbor=${this.actions.focus_on_neighbor}
                            disable_input=${this.state.disable_ui || !this.state.connected /* && this.state.binder_phase == null*/}
                            last_created_cell=${this.state.last_created_cell}
                            selected_cells=${this.state.selected_cells}
                            is_initializing=${this.state.initializing}
                            is_process_ready=${
                                this.state.notebook.process_status === ProcessStatus.starting || this.state.notebook.process_status === ProcessStatus.ready
                            }
                            disable_input=${!this.state.connected}
                        />
                        <${DropRuler}
                            actions=${this.actions}
                            selected_cells=${this.state.selected_cells}
                            set_scroller=${(enabled) => {
                                this.setState({ scroller: enabled })
                            }}
                            serialize_selected=${this.serialize_selected}
                        />
                        ${
                            this.state.disable_ui ||
                            html`<${SelectionArea}
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
                            />`
                        }
                    </${Main}>
                    <${FindReplace} />
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
                                <a href="https://github.com/fonsp/Pluto.jl/wiki" target="_blank">FAQ</a>
                                <span style="flex: 1"></span>
                                <label for="opinion">🙋 How can we make <a href="https://github.com/fonsp/Pluto.jl" target="_blank">Pluto.jl</a> better?</label>
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
