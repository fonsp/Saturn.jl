// as per https://stackoverflow.com/questions/123999/how-can-i-tell-if-a-dom-element-is-visible-in-the-current-viewport/7557433#7557433
const isElementVisible = (element) => {
    const boundingRectangle = element.getBoundingClientRect()
    return (
        boundingRectangle.top >= 0 &&
        boundingRectangle.left >= 0 &&
        boundingRectangle.bottom <= (window.innerHeight || document.documentElement.clientHeight) &&
        boundingRectangle.right <= (window.innerWidth || document.documentElement.clientWidth)
    )
}

const scrollToCodeMirrorIfNeeded = (codemirror) => {
    const wrapperElement = codemirror.getWrapperElement()
    if (!isElementVisible(wrapperElement)) {
        codemirror.getWrapperElement().scrollIntoView({
            behaviour: "auto",
            block: "center",
            inline: "center",
        })
    }
}
/**
 * Wraps the CodeMirror TextMarker, enhanced by some context information and
 * convenient functionality. Used to keep a reference to matches found by the
 * find-replace procedure.
 */
export default class TextMarker {
    /**
     * @param {string} id Simply used to later identify an instance
     * @param {window.CodeMirror} codemirror CodeMirror instance that contains the matched text
     * @param {number} from Begin of the matched text
     * @param {number} to End of the matched text
     */
    constructor(id, codemirror, from, to) {
        this.id = id
        this.codemirror = codemirror
        this.from = from
        this.to = to
        this.marker = null
        this.highlight()
    }
    offset(by) {
        this.to.ch = this.to.ch + by
        this.from.ch = this.from.ch + by
    }
    /**
     * Selects the matched text (selections are the ones that are replaced)
     */
    select() {
        this.marker = this.codemirror.markText(this.from, this.to, { css: "background: #D9D5D5; color: red; font-weight: bold" })
        scrollToCodeMirrorIfNeeded(this.codemirror)
    }

    /**
     * Deselects the matched text
     */
    deselect() {
        if (this.marker) {
            this.marker.clear()
        }
    }

    /**
     * Replaces the matched text
     * @param {string} word Word replacing the matched text
     */
    replace_with(word) {
        this.codemirror.replaceRange(word, this.from, this.to)
    }

    /**
     * Clears the highlighting of the matched text
     */
    clear_highlighting() {
        this.highlighter.clear()
        window.CodeMirror.signal(this.codemirror, "custom_event_set_visible", false)
    }

    /**
     * @private
     */
    highlight() {
        this.highlighter = this.codemirror.markText(this.from, this.to, { css: "color: red; font-weight: bold" })
        window.CodeMirror.signal(this.codemirror, "custom_event_set_visible", true)
    }
}
