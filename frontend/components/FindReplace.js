import TextMarker from "../common/TextMarker.js"
import { html, useState, useRef, useEffect } from "../imports/Preact.js"

const enter_key = 13

const get_codeMirrors = () => {
    return Array.from(document.querySelectorAll("pluto-input .CodeMirror")).map((cm_node) => ({
        cell_id: cm_node.parentElement.parentElement.id,
        cm: cm_node.CodeMirror,
    }))
}

export const FindReplace = () => {
    // for reference!!
    const [word, set_word] = useState("")
    const [visible, set_visible] = useState(false)
    const [textmarkers, set_textmarkers] = useState([])
    const [marker, set_marker] = useState(null)
    const [invalid_regex, set_invalid_regex] = useState(null)

    const [replace_value, set_replace_value] = useState(null)
    const input_find = useRef(null)
    const clear_all_markers = () => {
        textmarkers.forEach((each_marker) => {
            each_marker?.clear_highlighting()
            each_marker?.deselect()
        })
    }

    const try_as_regex = (word) => {
        try {
            var regex_word = new RegExp(word.substring(1, word.length - 1))
            set_invalid_regex(false)
            return regex_word
        } catch (e) {
            set_invalid_regex(true)
        }
        return word
    }

    const preprocess_word = (word) => {
        set_invalid_regex(false)
        var is_regex_candidate = word && word.length > 2 && word[0] == "/" && word.slice(-1) == "/"
        return is_regex_candidate ? try_as_regex(word) : word
    }

    const processedWord = preprocess_word(word)
    const create_textmarkers = (replaceText) => {
        clear_all_markers()
        const tms = get_codeMirrors().flatMap(({ cell_id, cm }) => {
            const localCursors = []
            const cursor = cm.getSearchCursor(processedWord)
            while (cursor.findNext()) {
                if (replaceText) cursor.replace(replaceText)
                const textmarker = new TextMarker(cell_id, cm, cursor.from(), cursor.to())
                localCursors.push(textmarker)
            }
            return localCursors
        })
        set_textmarkers(tms)
        const [firstmarker] = tms
        set_marker(firstmarker)
        firstmarker?.select()
        return firstmarker
    }

    const find_next = () => {
        const { length } = textmarkers
        const markerIndex = textmarkers.indexOf(marker)

        // last in the list
        if (markerIndex + 1 == length) {
            create_textmarkers()
            return
        }

        const nextMarker = textmarkers[(markerIndex + 1) % length]
        console.log(nextMarker, "nextmarker")
        if (nextMarker) {
            const { cm, from, to } = nextMarker
            cm?.scrollIntoView({ from, to })
        }
        set_marker(nextMarker)
        marker?.deselect()
        nextMarker?.select()
    }

    const replace_with = (word_to_replace_with) => {
        marker?.replace_with(word_to_replace_with ?? "")
        // Now we need to recalculate the markers of this codemirror, starting at the new end position of marker.
        // replace (even if nothing is selected) results in a find-next
        // recalculate all markers!
        if (!word_to_replace_with) {
            const i = textmarkers.indexOf(marker)
            const next_i = (i + 1) % textmarkers.length
            const next = next_i !== i ? textmarkers[next_i] : null
            set_textmarkers(textmarkers.filter((tm) => tm !== marker))
            set_marker(next)
        } else {
            find_next()
        }
    }

    const replace_all = (with_word = "") => {
        clear_all_markers()
        get_codeMirrors().forEach(({ cell_id, cm }) => {
            const localCursors = []
            const cursor = cm.getSearchCursor(word)
            while (cursor.findNext()) {
                if (with_word) cursor.replace(with_word)
            }
            return localCursors
        })
        create_textmarkers()
    }
    const throttle_set_word = _.throttle((word) => set_word(word), 120)

    const handle_find_value_change = (event) => {
        // Enter
        if (event.keyCode === enter_key) {
            find_next()
        } else {
            throttle_set_word(event.target.value)
        }
    }

    const jump_to_find = () => {
        input_find.current?.focus()
        // Not fixed yet: Must only be carried out upon either selecting a new word or opening the panel
        //input_find.current.select()
    }
    const handler = (ev) => {
        const { composedPath, ctrlKey, key, path: p } = ev
        const path = p || ev.composedPath()
        if (key === "Escape") {
            clear_all_markers()
            set_visible(false)
        }
        if (!((ctrlKey && key === "f") || (ctrlKey && key === "h") || key === "F3")) return
        // Don't open normal find
        ev.preventDefault()
        // Find CM if in event path
        const cm = path.find(({ CodeMirror }) => CodeMirror)?.CodeMirror
        const selections = cm?.getSelections?.()
        if (cm && selections?.length) {
            clear_all_markers()
            input_find.current.value = selections[0]
            set_word(selections[0])
            set_visible(true)
            create_textmarkers()
        } else {
            !visible ? create_textmarkers() : clear_all_markers()
            set_visible(!visible)
        }
    }
    useEffect(() => {
        document.body.addEventListener("keydown", handler)
        return () => document.body.removeEventListener("keydown", handler)
    }, [handler])

    useEffect(() => {
        if (visible && input_find.current) jump_to_find()
    }, [visible, input_find.current])

    useEffect(() => {
        const firstmarker = create_textmarkers()
        return () => firstmarker?.deselect()
    }, [word])

    return html`<div id="findreplace">
        <aside id="findreplace_container" class=${visible ? "show_findreplace" : ""}>
            <div id="findform">
                <input
                    id="value_input"
                    type="text"
                    class=${invalid_regex ? "findreplace_invalid_regex" : ""}
                    ref=${input_find}
                    onKeyUp=${handle_find_value_change}
                />
                <button onClick=${find_next}>Next</button>
                <output>${textmarkers?.indexOf(marker) + 1 || "?"}/${textmarkers?.length || 0}</output>
            </div>
            <div id="replaceform">
                <input
                    type="text"
                    value=${replace_value}
                    onKeyUp=${(ev) => {
                        set_replace_value(ev.target.value)
                    }}
                />
                <button onClick=${() => replace_with(replace_value)}>Replace</button>
                <button onClick=${() => replace_all(replace_value)}>All</button>
            </div>
        </aside>
    </div>`
}
