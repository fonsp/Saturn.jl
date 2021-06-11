export let is_mac_keyboard = /Mac/.test(navigator.platform)

export let ctrl_or_cmd_name = is_mac_keyboard ? "⌘" : "Ctrl"
export let alt_or_option_name = is_mac_keyboard ? "⌥" : "Alt"

export let has_ctrl_or_cmd_pressed = (event) => event.ctrlKey || (is_mac_keyboard && event.metaKey)

export let map_cmd_to_ctrl_on_mac = (keymap) => {
    if (!is_mac_keyboard) {
        return keymap
    }

    let keymap_with_cmd = { ...keymap }
    for (let [key, handler] of Object.entries(keymap)) {
        keymap_with_cmd[key.replace(/Ctrl/g, "Cmd")] = handler
    }
    return keymap_with_cmd
}

export let in_textarea_or_input = () => {
    const { tagName } = document.activeElement
    return tagName === "INPUT" || tagName === "TEXTAREA"
}
