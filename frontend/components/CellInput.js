import { html, useState, useEffect, useLayoutEffect, useRef, useContext } from "../imports/Preact.js"
import observablehq_for_myself from "../common/SetupCellEnvironment.js"

import { utf8index_to_ut16index } from "../common/UnicodeTools.js"
import { has_ctrl_or_cmd_pressed, map_cmd_to_ctrl_on_mac } from "../common/KeyboardShortcuts.js"
import { PlutoContext } from "../common/PlutoContext.js"

//@ts-ignore
import { mac, chromeOS } from "https://cdn.jsdelivr.net/gh/codemirror/CodeMirror@5.60.0/src/util/browser.js"
import {
    EditorState,
    EditorView,
    Compartment,
    EditorSelection,
    basicSetup,
    StreamLanguage,
    julia,
    keymap,
    history,
    historyKeymap,
    defaultKeymap,
    indentMore,
    indentLess,
} from "https://cdn.jsdelivr.net/gh/JuliaPluto/codemirror-pluto-setup@8697d451b4d1bb25bb0d772e857f8a3802cdc279/dist/index.es.min.js"

// Compartments: https://codemirror.net/6/examples/config/
let editable = new Compartment()

const getValue6 = (cm) => cm.state.doc.toString()
const setValue6 = (cm, value) =>
    cm.dispatch({
        changes: { from: 0, to: cm.state.doc.length, insert: value },
    })
const replaceRange6 = (cm, text, from, to) =>
    cm.dispatch({
        changes: { from, to, insert: text },
    })
const setSelection6 = (cm, anchor, head) => cm.dispatch({ selection: { anchor, head } })
const setSelections6 = (cm, ranges) => cm.dispatch({ selection: EditorSelection.create(ranges) })
const getSelections6 = (cm) => cm.state.selection.ranges.map((r) => cm.state.sliceDoc(r.from, r.to))
const listSelections6 = (cm) => cm.state.selection.ranges
const getCursor6 = (cm) => cm.state.selection.main.head
// @ts-ignore
const CodeMirror = window.CodeMirror

const clear_selection = (cm) => {
    const c = cm.getCursor()
    cm.setSelection(c, c, { scroll: false })
}

const last = (x) => x[x.length - 1]
const all_equal = (x) => x.every((y) => y === x[0])

// Adapted from https://gomakethings.com/how-to-test-if-an-element-is-in-the-viewport-with-vanilla-javascript/
var offsetFromViewport = function (elem) {
    let bounding = elem.getBoundingClientRect()
    let is_in_viewport = bounding.top >= 0 && bounding.bottom <= window.innerHeight
    if (is_in_viewport) {
        return null
    } else {
        return {
            top: bounding.top < 0 ? -bounding.top : window.innerHeight - bounding.bottom,
        }
    }
}

/**
 * @param {{
 *  local_code: string,
 *  remote_code: string,
 *  scroll_into_view_after_creation: boolean,
 *  [key: string]: any,
 * }} props
 */
export const CellInput = ({
    local_code,
    remote_code,
    disable_input,
    focus_after_creation,
    cm_forced_focus,
    set_cm_forced_focus,
    show_input,
    on_submit,
    on_delete,
    on_add_after,
    on_change,
    on_update_doc_query,
    on_focus_neighbor,
    on_drag_drop_events,
    cell_id,
    notebook_id,
}) => {
    let pluto_actions = useContext(PlutoContext)

    const cm_ref = useRef(null)
    const newcm_ref = useRef(null)
    const text_area_ref = useRef(null)
    const dom_node_ref = useRef(/** @type {HTMLElement} */ (null))
    const remote_code_ref = useRef(null)
    const on_change_ref = useRef(null)
    on_change_ref.current = on_change
    const disable_input_ref = useRef(disable_input)

    const time_last_being_force_focussed_ref = useRef(0)
    const time_last_genuine_backspace = useRef(0)

    useEffect(() => {
        /** Migration #1: Old */
        const current_value = cm_ref.current?.getValue() ?? ""
        if (remote_code_ref.current == null && remote_code === "" && current_value !== "") {
            // this cell is being initialized with empty code, but it already has local code set.
            // this happens when pasting or dropping cells
            return
        }
        remote_code_ref.current = remote_code
        if (current_value !== remote_code) {
            cm_ref.current?.setValue(remote_code)
        }
    }, [remote_code])

    useEffect(() => {
        /** Migration #1: New */
        const current_value = getValue6(newcm_ref.current) ?? ""
        if (remote_code_ref.current == null && remote_code === "" && current_value !== "") {
            // this cell is being initialized with empty code, but it already has local code set.
            // this happens when pasting or dropping cells
            return
        }
        remote_code_ref.current = remote_code
        if (current_value !== remote_code) {
            setValue6(newcm_ref.current, remote_code)
        }
    }, [remote_code])

    useLayoutEffect(() => {
        /** Migration #0: OLD */
        const cm = (cm_ref.current = CodeMirror.fromTextArea(text_area_ref.current, {
            value: local_code, // Migrated
            lineNumbers: true, // TODO: Styles
            mode: "julia", // Migrated
            lineWrapping: true, // TODO
            viewportMargin: Infinity, // TODO
            dragDrop: false /* Performance is too bad. 
            - Before: https://user-images.githubusercontent.com/6933510/116729854-fcdfd880-a9e7-11eb-9c88-f88f31ac352e.mov 
            - After: https://user-images.githubusercontent.com/6933510/116729764-d91c9280-a9e7-11eb-82df-d2f804630394.mov */,
            placeholder: "Enter cell code...", // Migrated
            indentWithTabs: true, // TODO
            indentUnit: 4, // TODO
            hintOptions: {
                // TODO
                hint: juliahints,
                pluto_actions: pluto_actions,
                notebook_id: notebook_id,
                on_update_doc_query: on_update_doc_query,
                extraKeys: {
                    ".": (cm, { pick }) => {
                        pick()
                        cm.replaceSelection(".")
                        cm.showHint()
                    },
                    // "(": (cm, { pick }) => pick(),
                },
            },
            matchBrackets: true, // Migrated
            configureMouse: (cm, repeat, event) => {
                // modified version of https://github.com/codemirror/CodeMirror/blob/bd1b7d2976d768ae4e3b8cf209ec59ad73c0305a/src/edit/mouse_events.js#L116-L127
                // because we want to change keys to match vs code
                let alt = chromeOS ? event.metaKey : event.altKey
                let rect = event.shiftKey && alt
                return {
                    unit: rect ? "rectangle" : repeat == "single" ? "char" : repeat == "double" ? "word" : "line",
                    addNew: rect ? false : alt,
                }
            },
        }))

        const keyMapSubmit = () => on_submit()
        const keyMapRun = async () => {
            // we await to prevent an out-of-sync issue
            await on_add_after()

            const new_value = newcm_ref.current?.state.doc.toString() ?? ""
            if (new_value !== remote_code_ref.current) {
                on_submit()
            }
        }
        const keyMapTab =  // work todo
            (shift) =>
            (...args) => {
                const cm = newcm_ref.current
                const to = getCursor6(cm) // Do for whole selected line
                const from = cm.state.doc.lineAt(getCursor6(cm)).from
                const text = cm.state.sliceDoc(from, to)
                const lastChar = cm.state.sliceDoc(to - 1, to)
                console.table({ to, from, text })
                if (text?.trim()?.length === 0) {
                    ;(shift && indentLess(...args)) || indentMore(...args)
                } else {
                    if (shift && lastChar === `\t`) replaceRange6(cm, ``, to - 1, to)
                    if (!shift) replaceRange6(cm, `${lastChar}\t`, to - 1, to)
                }
            }
        const keyMapPageUp = () => on_focus_neighbor(cell_id, -1, 0, 0)
        const keyMapPageDown = () => on_focus_neighbor(cell_id, +1, 0, 0)
        const keyMapMD = () => {
            // Migrated
            const cm = newcm_ref.current
            const value = getValue6(cm)
            const trimmed = value.trim()
            const offset = value.length - value.trimStart().length
            console.table({ value, trimmed, offset })
            if (trimmed.startsWith('md"') && trimmed.endsWith('"')) {
                // Markdown cell, change to code
                let start, end
                if (trimmed.startsWith('md"""') && trimmed.endsWith('"""')) {
                    // Block markdown
                    start = 5
                    end = trimmed.length - 3
                } else {
                    // Inline markdown
                    start = 3
                    end = trimmed.length - 1
                }
                if (start >= end || trimmed.substring(start, end).trim() == "") {
                    // Corner case: block is empty after removing markdown
                    setValue6(cm, "")
                } else {
                    while (/\s/.test(trimmed[start])) {
                        ++start
                    }
                    while (/\s/.test(trimmed[end - 1])) {
                        --end
                    }
                    // Keep the selection from [start, end) while maintaining cursor position
                    replaceRange6(cm, "", end + offset, cm.state.doc.length)
                    // cm.replaceRange("", cm.posFromIndex(end + offset), { line: cm.lineCount() })
                    replaceRange6(cm, "", 0, start + offset)
                    // cm.replaceRange("", { line: 0, ch: 0 }, cm.posFromIndex(start + offset))
                }
            } else {
                // Replacing ranges will maintain both the focus, the selections and the cursor
                replaceRange6(cm, `md"""\n`, 0, 0)
                replaceRange6(cm, `\n"""`, cm.state.doc.length, cm.state.doc.length)
            }
        }
        const keyMapD = () => {
            const cm = newcm_ref.current
        }
        const keyMapDelete = () => {
            const cm = newcm_ref.current
            if (disable_input_ref.current) {
                return
            }
            if (cm.state.doc.lines === 1 && getValue6(cm) === "") {
                on_focus_neighbor(cell_id, +1)
                on_delete()
            }
            return CodeMirror.Pass
        }
        const plutoKeyMaps = [
            /** Migration #3: New code */ { key: "Shift-Enter", run: keyMapSubmit, preventDefault: true },
            { key: "Ctrl-Enter", run: keyMapRun, preventDefault: true },
            { key: "PageUp", run: keyMapPageUp, preventDefault: true },
            { key: "PageDown", run: keyMapPageDown, preventDefault: true },
            { key: "Tab", run: keyMapTab(false), shift: keyMapTab(true), preventDefault: true },
            { key: "Ctrl-m", run: keyMapMD, preventDefault: true },
            // Codemirror6 doesn't like capslock
            { key: "Ctrl-M", run: keyMapMD, preventDefault: true },
            { key: "Ctrl-d", run: keyMapD, preventDefault: true },
            { key: "Ctrl-D", run: keyMapD, preventDefault: true },
            { key: "Ctrl-D", run: keyMapD, preventDefault: true },
            { key: "Delete", run: keyMapDelete, preventDefault: true },
            { key: "Ctrl-Delete", run: keyMapDelete, preventDefault: true },
        ]
        const onCM6Update = (update) => {
            if (update.docChanged) {
                const cm = newcm_ref.current
                const new_value = getValue6(cm)
                console.log(new_value)
                if (new_value.length > 1 && new_value[0] === "?") {
                    console.log("yeap")
                    window.dispatchEvent(new CustomEvent("open_live_docs"))
                }
                on_change_ref.current(new_value)
            }
        }
        const newcm = (newcm_ref.current = new EditorView({
            /** Migration #0: New */
            state: EditorState.create({
                doc: local_code,

                extensions: [
                    EditorState.tabSize.of(4),
                    basicSetup,
                    EditorView.updateListener.of(onCM6Update),
                    editable.of(EditorView.editable.of(!disable_input_ref.current)),
                    history(),
                    keymap.of([...defaultKeymap, ...historyKeymap, ...plutoKeyMaps]),
                    StreamLanguage.define(julia),
                ],
            }),
            parent: dom_node_ref.current,
        }))
        /** Migration #3: Old code */
        const keys = {}
        // Migrated
        keys["Shift-Enter"] = () => on_submit()
        // Migrated
        keys["Ctrl-Enter"] = async () => {
            // we await to prevent an out-of-sync issue
            await on_add_after()

            const new_value = cm.getValue()
            if (new_value !== remote_code_ref.current) {
                on_submit()
            }
        }
        // Page up and page down are fn+Up and fn+Down on recent apple keyboards
        //Migrated
        keys["PageUp"] = () => {
            on_focus_neighbor(cell_id, -1, 0, 0)
        }
        //Migrated
        keys["PageDown"] = () => {
            on_focus_neighbor(cell_id, +1, 0, 0)
        }
        keys["Shift-Tab"] = "indentLess" // TODO
        keys["Tab"] = on_tab_key // TODO
        keys["Ctrl-Space"] = () => cm.showHint() //TODO
        keys["Ctrl-D"] = () => {
            // TODO
            if (cm.somethingSelected()) {
                const sels = cm.getSelections()
                if (all_equal(sels)) {
                    // TODO
                }
            } else {
                const cursor = cm.getCursor()
                const token = cm.getTokenAt(cursor)
                cm.setSelection({ line: cursor.line, ch: token.start }, { line: cursor.line, ch: token.end })
            }
        }

        // Default config
        keys["Ctrl-/"] = () => {
            const old_value = cm.getValue()
            cm.toggleComment({ indent: true })
            const new_value = cm.getValue()
            if (old_value === new_value) {
                // the commenter failed for some reason
                // this happens when lines start with `md"`, with no indent
                cm.setValue(cm.lineCount() === 1 ? `# ${new_value}` : `#= ${new_value} =#`)
                cm.execCommand("selectAll")
            }
        }

        // Migrated
        keys["Ctrl-M"] = () => {
            const value = cm.getValue()
            const trimmed = value.trim()
            const offset = value.length - value.trimStart().length
            if (trimmed.startsWith('md"') && trimmed.endsWith('"')) {
                // Markdown cell, change to code
                let start, end
                if (trimmed.startsWith('md"""') && trimmed.endsWith('"""')) {
                    // Block markdown
                    start = 5
                    end = trimmed.length - 3
                } else {
                    // Inline markdown
                    start = 3
                    end = trimmed.length - 1
                }
                if (start >= end || trimmed.substring(start, end).trim() == "") {
                    // Corner case: block is empty after removing markdown
                    cm.setValue("")
                } else {
                    while (/\s/.test(trimmed[start])) {
                        ++start
                    }
                    while (/\s/.test(trimmed[end - 1])) {
                        --end
                    }
                    // Keep the selection from [start, end) while maintaining cursor position
                    cm.replaceRange("", cm.posFromIndex(end + offset), { line: cm.lineCount() })
                    cm.replaceRange("", { line: 0, ch: 0 }, cm.posFromIndex(start + offset))
                }
            } else {
                // Code cell, change to markdown
                const old_selections = cm.listSelections()
                cm.setValue(`md"""\n${value}\n"""`)
                // Move all selections down a line
                const new_selections = old_selections.map(({ anchor, head }) => {
                    return {
                        anchor: { ...anchor, line: anchor.line + 1 },
                        head: { ...head, line: head.line + 1 },
                    }
                })
                cm.setSelections(new_selections)
            }
        }
        const swap = (a, i, j) => {
            ;[a[i], a[j]] = [a[j], a[i]]
        }
        const range = (a, b) => {
            const x = Math.min(a, b)
            const y = Math.max(a, b)
            return [...Array(y + 1 - x).keys()].map((i) => i + x)
        }
        const alt_move = (delta) => {
            const selections = cm.listSelections()
            const selected_lines = new Set([].concat(...selections.map((sel) => range(sel.anchor.line, sel.head.line))))
            const final_line_number = delta === 1 ? cm.lineCount() - 1 : 0
            if (!selected_lines.has(final_line_number)) {
                Array.from(selected_lines)
                    .sort((a, b) => (delta * a < delta * b ? 1 : -1))
                    .forEach((line_number) => {
                        const lines = cm.getValue().split("\n")
                        swap(lines, line_number, line_number + delta)
                        cm.setValue(lines.join("\n"))
                        cm.indentLine(line_number + delta, "smart")
                        cm.indentLine(line_number, "smart")
                    })
                cm.setSelections(
                    selections.map((sel) => {
                        return {
                            head: {
                                line: sel.head.line + delta,
                                ch: sel.head.ch,
                            },
                            anchor: {
                                line: sel.anchor.line + delta,
                                ch: sel.anchor.ch,
                            },
                        }
                    })
                )
            }
        }
        //Default
        keys["Alt-Up"] = () => alt_move(-1)
        // Default
        keys["Alt-Down"] = () => alt_move(+1)

        // TODO
        keys["Backspace"] = keys["Ctrl-Backspace"] = () => {
            if (disable_input_ref.current) {
                return
            }
            const BACKSPACE_CELL_DELETE_COOLDOWN = 300
            const BACKSPACE_AFTER_FORCE_FOCUS_COOLDOWN = 300

            if (cm.lineCount() === 1 && cm.getValue() === "") {
                // I wanted to write comments, but I think my variable names are documentation enough
                let enough_time_passed_since_last_backspace = Date.now() - time_last_genuine_backspace.current > BACKSPACE_CELL_DELETE_COOLDOWN
                let enough_time_passed_since_force_focus = Date.now() - time_last_being_force_focussed_ref.current > BACKSPACE_AFTER_FORCE_FOCUS_COOLDOWN
                if (enough_time_passed_since_last_backspace && enough_time_passed_since_force_focus) {
                    on_focus_neighbor(cell_id, -1)
                    on_delete()
                }
            }

            let enough_time_passed_since_force_focus = Date.now() - time_last_being_force_focussed_ref.current > BACKSPACE_AFTER_FORCE_FOCUS_COOLDOWN
            if (enough_time_passed_since_force_focus) {
                time_last_genuine_backspace.current = Date.now()
                return CodeMirror.Pass
            } else {
                // Reset the force focus timer, as I want it to act like a debounce, not just a delay
                time_last_being_force_focussed_ref.current = Date.now()
            }
        }
        // Mirgated
        keys["Delete"] = keys["Ctrl-Delete"] = () => {
            if (disable_input_ref.current) {
                return
            }
            if (cm.lineCount() === 1 && cm.getValue() === "") {
                on_focus_neighbor(cell_id, +1)
                on_delete()
            }
            return CodeMirror.Pass
        }

        /** Basically any variable inside an useEffect is already a ref
         * so I'll just roll with this abstraction
         * @param {(time_since: Number) => any} fn
         */
        let with_time_since_last = (fn) => {
            let last_invoke_time = -Infinity // This infinity is for you, Fons
            return () => {
                let result = fn(Date.now() - last_invoke_time)
                last_invoke_time = Date.now()
                return result
            }
        }
        const isapprox = (a, b) => Math.abs(a - b) < 3.0
        const at_first_line_visually = () => isapprox(cm.cursorCoords(null, "div").top, 0.0)
        keys["Up"] = with_time_since_last((elapsed) => {
            // TODO
            if (elapsed > 300 && at_first_line_visually()) {
                on_focus_neighbor(cell_id, -1, Infinity, Infinity)
                // todo:
                // on_focus_neighbor(cell_id, -1, Infinity, cm.getCursor().ch)
                // but this does not work if the last line in the previous cell wraps
                // and i can't figure out how to fix it in a simple way
            } else {
                return CodeMirror.Pass
            }
        })
        const at_first_position = () => cm.findPosH(cm.getCursor(), -1, "char")?.hitSide === true
        keys["Left"] = with_time_since_last((elapsed) => {
            // TODO
            if (elapsed > 300 && at_first_position()) {
                on_focus_neighbor(cell_id, -1, Infinity, Infinity)
            } else {
                return CodeMirror.Pass
            }
        })
        const at_last_line_visually = () => isapprox(cm.cursorCoords(null, "div").top, cm.cursorCoords({ line: Infinity, ch: Infinity }, "div").top)
        keys["Down"] = with_time_since_last((elapsed) => {
            // TODO
            if (elapsed > 300 && at_last_line_visually()) {
                on_focus_neighbor(cell_id, 1, 0, 0)
                // todo:
                // on_focus_neighbor(cell_id, 1, 0, cm.getCursor().ch)
                // same here
            } else {
                return CodeMirror.Pass
            }
        })
        const at_last_position = () => cm.findPosH(cm.getCursor(), 1, "char")?.hitSide === true
        keys["Right"] = with_time_since_last((elapsed) => {
            // TODO
            if (elapsed > 300 && at_last_position()) {
                on_focus_neighbor(cell_id, 1, 0, 0)
            } else {
                return CodeMirror.Pass
            }
        })
        const open_close_selection = (opening_char, closing_char) => () => {
            // Default
            if (cm.somethingSelected()) {
                for (const selection of cm.getSelections()) {
                    cm.replaceSelection(`${opening_char}${selection}${closing_char}`, "around")
                }
            } else {
                return CodeMirror.Pass
            }
        }

        ;["()", "{}", "[]"].forEach((pair) => {
            const [opening_char, closing_char] = pair.split("")
            keys[`'${opening_char}'`] = open_close_selection(opening_char, closing_char)
        })

        cm.setOption("extraKeys", map_cmd_to_ctrl_on_mac(keys))

        let is_good_token = (token) => {
            if (token.type == null && token.string === "]") {
                return true
            }

            // Symbol, and symbols don't have autocomplete 🤷‍♀️
            if (token.type === "builtin" && token.string.startsWith(":") && !token.string.startsWith("::")) {
                return false
            }
            let bad_token_types = ["number", "string", null]
            if (bad_token_types.includes(token.type)) {
                return false
            }
            return true
        }
        // TODO
        cm.on("dragover", (cm_, e) => {
            if (e.dataTransfer.types[0] !== "text/plain") {
                on_drag_drop_events(e)
                return true
            }
        })

        // TODO
        cm.on("drop", (cm_, e) => {
            if (e.dataTransfer.types[0] !== "text/plain") {
                on_drag_drop_events(e)
                e.preventDefault()
                return true
            }
        })

        // TODO
        cm.on("dragenter", (cm_, e) => {
            if (e.dataTransfer.types[0] !== "text/plain") {
                on_drag_drop_events(e)
                return true
            }
        })

        // TODO
        cm.on("dragleave", (cm_, e) => {
            if (e.dataTransfer.types[0] !== "text/plain") {
                on_drag_drop_events(e)
                return true
            }
        })

        // TODO
        cm.on("cursorActivity", () => {
            setTimeout(() => {
                if (!cm.hasFocus()) return
                if (cm.somethingSelected()) {
                    const sel = cm.getSelection()
                    if (!/[\s]/.test(sel)) {
                        // no whitespace
                        on_update_doc_query(sel)
                    }
                } else {
                    const cursor = cm.getCursor()
                    const token = cm.getTokenAt(cursor)
                    if (token.start === 0 && token.type === "operator" && token.string === "?") {
                        // https://github.com/fonsp/Pluto.jl/issues/321
                        const second_token = cm.getTokenAt({ ...cursor, ch: 2 })
                        on_update_doc_query(second_token.string)
                    } else {
                        const token_before_cursor = cm.getTokenAt(cursor)
                        const token_after_cursor = cm.getTokenAt({ ...cursor, ch: cursor.ch + 1 })

                        let before_and_after_token = [token_before_cursor, token_after_cursor]

                        // Fix for string macros
                        for (let possibly_string_macro of before_and_after_token) {
                            let match = possibly_string_macro.string.match(/([a-zA-Z]+)"/)
                            if (possibly_string_macro.type === "string" && match != null) {
                                return on_update_doc_query(`@${match[1]}_str`)
                            }
                        }

                        let good_token = before_and_after_token.find((x) => is_good_token(x))
                        if (good_token) {
                            let tokens = cm.getLineTokens(cursor.line)
                            let current_token = tokens.findIndex((x) => x.start === good_token.start && x.end === good_token.end)
                            on_update_doc_query(
                                module_expanded_selection({
                                    tokens_before_cursor: tokens.slice(0, current_token + 1),
                                    tokens_after_cursor: tokens.slice(current_token + 1),
                                })
                            )
                        }
                    }
                }
            }, 0)
        })

        // Migrated (cm6 uses an observer) TODO Live docs
        cm.on("change", (_, e) => {
            const new_value = cm.getValue()
            if (new_value.length > 1 && new_value[0] === "?") {
                window.dispatchEvent(new CustomEvent("open_live_docs"))
            }
            on_change_ref.current(new_value)
        })

        //TODO
        cm.on("blur", () => {
            // NOT a debounce:
            setTimeout(() => {
                if (document.hasFocus()) {
                    clear_selection(cm)
                    set_cm_forced_focus(null)
                }
            }, 100)
        })

        //TODO
        cm.on("paste", (cm, e) => {
            const topaste = e.clipboardData.getData("text/plain")
            if (topaste.match(/# ╔═╡ ........-....-....-....-............/g)?.length) {
                pluto_actions.add_deserialized_cells(topaste, -1)
                e.stopImmediatePropagation()
                e.preventDefault()
                e.codemirrorIgnore = true
            }
            e.stopPropagation()
        })

        //TODO
        cm.on("mousedown", (cm, e) => {
            const notebook = pluto_actions.get_notebook()
            const mycell = notebook?.cell_dependencies?.[cell_id]
            const used_variables = Object.keys(mycell?.upstream_cells_map || {})
            const { which } = e
            const path = e.path || e.composedPath()
            const isVariable = path[0]?.classList.contains("cm-variable")
            const varName = path[0]?.textContent
            if (has_ctrl_or_cmd_pressed(e) && which === 1 && isVariable && used_variables.includes(varName)) {
                e.preventDefault()
                document.querySelector(`[id='${encodeURI(varName)}']`).scrollIntoView()
                window.dispatchEvent(
                    new CustomEvent("cell_focus", {
                        detail: {
                            cell_id: mycell.upstream_cells_map[varName][0],
                            line: 0, // 1-based to 0-based index
                        },
                    })
                )
            }
        })
        if (focus_after_creation) {
            // TODO Smooth scroll into view?
            cm.focus()
            newcm_ref.current.focus()
        }

        // @ts-ignore
        document.fonts.ready.then(() => {
            cm.refresh()
        })
    }, [])

    // useEffect(() => {
    //     if (!remote_code.submitted_by_me) {
    //         cm_ref.current.setValue(remote_code.body)
    //     }
    // }, [remote_code.timestamp])

    useEffect(() => {
        disable_input_ref.current = disable_input
        cm_ref.current.options.disableInput = disable_input
        newcm_ref.current.dispatch({
            effects: editable.reconfigure(EditorView.editable.of(!disable_input)),
        })
    }, [disable_input])

    useEffect(() => {
        if (cm_forced_focus == null) {
            clear_selection(cm_ref.current)
        } else {
            time_last_being_force_focussed_ref.current = Date.now()
            let cm_forced_focus_mapped = cm_forced_focus.map((x) => (x.line === Infinity ? { ...x, line: cm_ref.current.lastLine() } : x))
            cm_ref.current.focus()
            cm_ref.current.setSelection(...cm_forced_focus_mapped)
        }
    }, [cm_forced_focus])

    // fix a visual glitch where the input is only 5px high after unfolding the cell
    // Mirgration: Not needed?
    useEffect(() => {
        if (show_input) {
            cm_ref.current.refresh()
        }
    }, [show_input])

    // TODO effect hook for disable_input?

    return html`
        <pluto-input ref=${dom_node_ref}>
            <button onClick=${on_delete} class="delete_cell" title="Delete cell"><span></span></button>
            <textarea ref=${text_area_ref}></textarea>
        </pluto-input>
    `
}

const no_autocomplete = " \t\r\n([])+-=/,;'\"!#$%^&*~`<>|"

// TODO
const on_tab_key = (cm) => {
    const cursor = cm.getCursor()
    const old_line = cm.getLine(cursor.line)

    if (cm.somethingSelected()) {
        cm.indentSelection()
    } else {
        if (cursor.ch > 0 && no_autocomplete.indexOf(old_line[cursor.ch - 1]) == -1) {
            cm.showHint()
        } else {
            cm.replaceSelection("\t")
        }
    }
}

// TODO
const juliahints = (cm, options) => {
    const cursor = cm.getCursor()
    const old_line = cm.getLine(cursor.line)
    const old_line_sliced = old_line.slice(0, cursor.ch)

    return options.pluto_actions.send("complete", { query: old_line_sliced }, { notebook_id: options.notebook_id }).then(({ message }) => {
        const completions = {
            list: message.results.map(([text, type_description, is_exported]) => ({
                text: text,
                className: (is_exported ? "" : "c_notexported ") + (type_description == null ? "" : "c_" + type_description),
                // render: (el) => el.appendChild(observablehq_for_myself.html`<div></div>`),
            })),
            from: CodeMirror.Pos(cursor.line, utf8index_to_ut16index(old_line, message.start)),
            to: CodeMirror.Pos(cursor.line, utf8index_to_ut16index(old_line, message.stop)),
        }
        CodeMirror.on(completions, "select", (val) => {
            let text = typeof val === "string" ? val : val.text
            let doc_query = module_expanded_selection({
                tokens_before_cursor: [
                    { type: "variable", string: old_line_sliced.slice(0, completions.from.ch) },
                    { type: "variable", string: text },
                ],
                tokens_after_cursor: [],
            })
            options.on_update_doc_query(doc_query)
        })
        return completions
    })
}

// https://github.com/fonsp/Pluto.jl/issues/239
const module_expanded_selection = ({ tokens_before_cursor, tokens_after_cursor }) => {
    // Fix for :: type definitions, more specifically :: type definitions with { ... } generics
    // e.g. ::AbstractArray{String} gets parsed by codemirror as [`::AbstractArray{`, `String}`] ??
    let i_guess_current_token = tokens_before_cursor[tokens_before_cursor.length - 1]
    if (i_guess_current_token?.type === "builtin" && i_guess_current_token.string.startsWith("::")) {
        let typedef_tokens = []
        typedef_tokens.push(i_guess_current_token.string.slice(2))
        for (let token of tokens_after_cursor) {
            if (token.type !== "builtin") break
            typedef_tokens.push(token.string)
        }
        return typedef_tokens.join("")
    }

    // Fix for multi-character operators (|>, &&, ||), codemirror splits these up, so we have to stitch them back together.
    if (i_guess_current_token?.type === "operator") {
        let operator_tokens = []
        for (let token of tokens_before_cursor.reverse()) {
            if (token.type !== "operator") {
                break
            }
            operator_tokens.unshift(token.string)
        }
        for (let token of tokens_after_cursor) {
            if (token.type !== "operator") {
                break
            }
            operator_tokens.push(token.string)
        }
        return operator_tokens.join("")
    }

    let found = []
    /** @type {"top" | "in-ref"} */
    let state = "top"
    for (let token of tokens_before_cursor.slice().reverse()) {
        if (state === "top") {
            if (token.type == null && token.string == "]") {
                state = "in-ref"
                found.push(token.string)
                continue
            }
            if (token.type == null) {
                break
            }
            if (token.type === "number") {
                break
            }
            if (token.type === "builtin" && token.string.startsWith("::")) {
                found.push(token.string.slice(2))
                break
            }
            found.push(token.string)
        } else if (state === "in-ref") {
            if (token.type == null && token.string == "[") {
                state = "top"
                found.push(token.string)
                continue
            }
            if (token.type === "number" || token.type === "string") {
                found.push(token.string)
                continue
            }
            break
        }
    }
    return found.reverse().join("").replace(/\.$/, "")
}
