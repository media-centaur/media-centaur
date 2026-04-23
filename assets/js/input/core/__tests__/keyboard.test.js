import { describe, expect, test, beforeEach, mock } from "bun:test"
import { KeyboardSource } from "../keyboard"
import { Action } from "../actions"

function createMockDocument() {
  const listeners = {}
  return {
    addEventListener(type, fn) {
      listeners[type] = listeners[type] || []
      listeners[type].push(fn)
    },
    removeEventListener(type, fn) {
      if (listeners[type]) {
        listeners[type] = listeners[type].filter(f => f !== fn)
      }
    },
    _listeners: listeners,
    _dispatchKeyDown(key, opts = {}) {
      const event = {
        key,
        target: opts.target || { closest: () => null, tagName: "DIV" },
        ctrlKey: false,
        metaKey: false,
        altKey: false,
        preventDefault: mock(() => {}),
        stopPropagation: mock(() => {}),
        ...opts,
      }
      for (const fn of (listeners.keydown || [])) {
        fn(event)
      }
      return event
    },
  }
}

describe("KeyboardSource", () => {
  let doc, actions, inputDetections, source

  beforeEach(() => {
    doc = createMockDocument()
    actions = []
    inputDetections = []
    source = new KeyboardSource({
      document: doc,
      onAction: (action) => actions.push(action),
      onInputDetected: (type) => inputDetections.push(type),
    })
    source.start()
  })

  describe("action production", () => {
    test("arrow keys produce navigation actions", () => {
      doc._dispatchKeyDown("ArrowUp")
      doc._dispatchKeyDown("ArrowDown")
      doc._dispatchKeyDown("ArrowLeft")
      doc._dispatchKeyDown("ArrowRight")

      expect(actions).toEqual([
        Action.NAVIGATE_UP,
        Action.NAVIGATE_DOWN,
        Action.NAVIGATE_LEFT,
        Action.NAVIGATE_RIGHT,
      ])
    })

    test("Enter produces SELECT action", () => {
      doc._dispatchKeyDown("Enter")
      expect(actions).toEqual([Action.SELECT])
    })

    test("Escape produces BACK action", () => {
      doc._dispatchKeyDown("Escape")
      expect(actions).toEqual([Action.BACK])
    })

    test("p produces PLAY action", () => {
      doc._dispatchKeyDown("p")
      expect(actions).toEqual([Action.PLAY])
    })

    test("bracket keys produce zone actions", () => {
      doc._dispatchKeyDown("]")
      doc._dispatchKeyDown("[")
      expect(actions).toEqual([Action.ZONE_NEXT, Action.ZONE_PREV])
    })

    test("unmapped keys produce no action", () => {
      doc._dispatchKeyDown("x")
      doc._dispatchKeyDown("F1")
      expect(actions).toEqual([])
    })
  })

  describe("preventDefault", () => {
    test("called for handled keys", () => {
      const event = doc._dispatchKeyDown("ArrowDown")
      expect(event.preventDefault).toHaveBeenCalled()
    })

    test("not called for unhandled keys", () => {
      const event = doc._dispatchKeyDown("x")
      expect(event.preventDefault).not.toHaveBeenCalled()
    })
  })

  describe("onInputDetected", () => {
    test("fires keydown on every key event", () => {
      doc._dispatchKeyDown("ArrowDown")
      doc._dispatchKeyDown("x")
      expect(inputDetections).toEqual(["keydown", "keydown"])
    })
  })

  describe("data-captures-keys bypass", () => {
    test("skips navigation when target has data-captures-keys ancestor", () => {
      const capturer = {
        closest: (sel) => sel === "[data-captures-keys]" ? capturer : null,
        tagName: "DIV",
      }
      const event = doc._dispatchKeyDown("ArrowDown", { target: capturer })

      expect(actions).toEqual([])
      expect(event.preventDefault).not.toHaveBeenCalled()
    })
  })

  describe("text input two-mode handling", () => {
    const makeInput = (value = "") => ({
      tagName: "INPUT",
      value,
      closest: () => null,
      dispatchEvent: mock(() => {}),
    })

    test("Enter on focused text input activates edit mode", () => {
      const input = makeInput()
      const event = doc._dispatchKeyDown("Enter", { target: input })

      expect(source._inputEditing).toBe(true)
      expect(event.preventDefault).toHaveBeenCalled()
      expect(actions).toEqual([]) // no SELECT action
    })

    test("arrow keys navigate when text input is focused but not editing", () => {
      const input = makeInput()
      doc._dispatchKeyDown("ArrowDown", { target: input })

      expect(actions).toEqual([Action.NAVIGATE_DOWN])
      expect(source._inputEditing).toBe(false)
    })

    test("printable char activates edit mode and passes through", () => {
      const input = makeInput()
      const event = doc._dispatchKeyDown("a", { target: input })

      expect(source._inputEditing).toBe(true)
      expect(event.preventDefault).not.toHaveBeenCalled()
      expect(actions).toEqual([]) // no action, key passes to input
    })

    test("in editing mode, all keys pass through", () => {
      const input = makeInput()
      // Enter to activate editing
      doc._dispatchKeyDown("Enter", { target: input })
      actions.length = 0

      // ArrowDown should pass through, not navigate
      const event = doc._dispatchKeyDown("ArrowDown", { target: input })
      expect(actions).toEqual([])
      expect(event.preventDefault).not.toHaveBeenCalled()
    })

    test("Enter exits editing mode", () => {
      const input = makeInput()
      // Activate editing
      doc._dispatchKeyDown("Enter", { target: input })
      expect(source._inputEditing).toBe(true)

      // Enter again exits editing
      const event = doc._dispatchKeyDown("Enter", { target: input })
      expect(source._inputEditing).toBe(false)
      expect(event.preventDefault).toHaveBeenCalled()
    })

    test("first Escape while editing exits edit mode and preserves the value", () => {
      const input = makeInput("hello")
      doc._dispatchKeyDown("Enter", { target: input })
      expect(source._inputEditing).toBe(true)

      const event = doc._dispatchKeyDown("Escape", { target: input })
      expect(source._inputEditing).toBe(false)
      expect(input.value).toBe("hello")
      expect(input.dispatchEvent).not.toHaveBeenCalled()
      expect(event.preventDefault).toHaveBeenCalled()
      expect(actions).toEqual([])
    })

    test("Escape when not editing with a non-empty value clears the value", () => {
      const input = makeInput("hello")

      const event = doc._dispatchKeyDown("Escape", { target: input })
      expect(input.value).toBe("")
      expect(input.dispatchEvent).toHaveBeenCalled()
      expect(source._inputEditing).toBe(false)
      expect(event.preventDefault).toHaveBeenCalled()
      expect(actions).toEqual([])
    })

    test("two-press Escape sequence: editing → exit mode → clear value", () => {
      const input = makeInput("hello")
      doc._dispatchKeyDown("Enter", { target: input })

      doc._dispatchKeyDown("Escape", { target: input })
      expect(input.value).toBe("hello")
      expect(source._inputEditing).toBe(false)

      doc._dispatchKeyDown("Escape", { target: input })
      expect(input.value).toBe("")
    })

    test("Escape when not editing with an empty value falls through to BACK", () => {
      const input = makeInput("")

      const event = doc._dispatchKeyDown("Escape", { target: input })
      expect(actions).toEqual([Action.BACK])
      expect(event.preventDefault).toHaveBeenCalled()
      expect(input.dispatchEvent).not.toHaveBeenCalled()
    })

    test("Escape while editing an empty input just exits edit mode", () => {
      const input = makeInput("")
      doc._dispatchKeyDown("Enter", { target: input })

      doc._dispatchKeyDown("Escape", { target: input })
      expect(input.dispatchEvent).not.toHaveBeenCalled()
      expect(source._inputEditing).toBe(false)
      expect(actions).toEqual([])
    })

    test("TEXTAREA elements handled same as INPUT", () => {
      const textarea = {
        tagName: "TEXTAREA",
        value: "",
        closest: () => null,
        dispatchEvent: mock(() => {}),
      }
      doc._dispatchKeyDown("Enter", { target: textarea })
      expect(source._inputEditing).toBe(true)
    })
  })

  describe("Backspace and Delete on text input", () => {
    const makeInput = (value = "") => ({
      tagName: "INPUT",
      value,
      closest: () => null,
      dispatchEvent: mock(() => {}),
    })

    test("Backspace on non-empty input enters edit mode and passes through to the browser", () => {
      const input = makeInput("matrix")

      const event = doc._dispatchKeyDown("Backspace", { target: input })
      expect(source._inputEditing).toBe(true)
      expect(event.preventDefault).not.toHaveBeenCalled()
      expect(actions).toEqual([])
    })

    test("Backspace on empty input falls through to CLEAR", () => {
      const input = makeInput("")

      const event = doc._dispatchKeyDown("Backspace", { target: input })
      expect(source._inputEditing).toBe(false)
      expect(actions).toEqual([Action.CLEAR])
      expect(event.preventDefault).toHaveBeenCalled()
    })

    test("Delete on non-empty input enters edit mode and passes through", () => {
      const input = makeInput("matrix")

      const event = doc._dispatchKeyDown("Delete", { target: input })
      expect(source._inputEditing).toBe(true)
      expect(event.preventDefault).not.toHaveBeenCalled()
      expect(actions).toEqual([])
    })

    test("Delete on empty input is unmapped and produces no action", () => {
      const input = makeInput("")

      const event = doc._dispatchKeyDown("Delete", { target: input })
      expect(source._inputEditing).toBe(false)
      expect(actions).toEqual([])
      expect(event.preventDefault).not.toHaveBeenCalled()
    })

    test("Backspace while editing passes through unchanged", () => {
      const input = makeInput("matrix")
      doc._dispatchKeyDown("Enter", { target: input })
      actions.length = 0

      const event = doc._dispatchKeyDown("Backspace", { target: input })
      expect(actions).toEqual([])
      expect(event.preventDefault).not.toHaveBeenCalled()
    })
  })

  describe("onEditingChanged callback", () => {
    let edits

    beforeEach(() => {
      source.stop()
      edits = []
      source = new KeyboardSource({
        document: doc,
        onAction: (action) => actions.push(action),
        onInputDetected: () => {},
        onEditingChanged: (editing) => edits.push(editing),
      })
      source.start()
    })

    const makeInput = (value = "") => ({
      tagName: "INPUT",
      value,
      closest: () => null,
      dispatchEvent: mock(() => {}),
    })

    test("fires true when Enter activates edit mode", () => {
      doc._dispatchKeyDown("Enter", { target: makeInput() })
      expect(edits).toEqual([true])
    })

    test("fires true when a printable character activates edit mode", () => {
      doc._dispatchKeyDown("a", { target: makeInput() })
      expect(edits).toEqual([true])
    })

    test("fires true when Backspace on a non-empty input activates edit mode", () => {
      doc._dispatchKeyDown("Backspace", { target: makeInput("hi") })
      expect(edits).toEqual([true])
    })

    test("fires false when Escape exits edit mode", () => {
      const input = makeInput("hi")
      doc._dispatchKeyDown("Enter", { target: input })
      doc._dispatchKeyDown("Escape", { target: input })
      expect(edits).toEqual([true, false])
    })

    test("fires false when Enter exits edit mode", () => {
      const input = makeInput()
      doc._dispatchKeyDown("Enter", { target: input })
      doc._dispatchKeyDown("Enter", { target: input })
      expect(edits).toEqual([true, false])
    })

    test("does not fire when arrow keys navigate past a focused input", () => {
      doc._dispatchKeyDown("ArrowDown", { target: makeInput() })
      expect(edits).toEqual([])
    })

    test("does not fire when the same state is re-asserted", () => {
      const input = makeInput("a")
      doc._dispatchKeyDown("Backspace", { target: input })
      doc._dispatchKeyDown("b", { target: input })
      expect(edits).toEqual([true])
    })
  })

  describe("lifecycle", () => {
    test("stop removes event listener", () => {
      source.stop()

      doc._dispatchKeyDown("ArrowDown")
      expect(actions).toEqual([])
    })

    test("no actions after stop", () => {
      source.stop()

      // Manually verify listener was removed
      expect(doc._listeners.keydown?.length ?? 0).toBe(0)
    })
  })

  describe("custom key map", () => {
    test("uses provided keyMap", () => {
      source.stop()
      actions.length = 0

      const customSource = new KeyboardSource({
        document: doc,
        keyMap: { w: Action.NAVIGATE_UP, s: Action.NAVIGATE_DOWN },
        onAction: (action) => actions.push(action),
        onInputDetected: () => {},
      })
      customSource.start()

      doc._dispatchKeyDown("w")
      doc._dispatchKeyDown("s")
      expect(actions).toEqual([Action.NAVIGATE_UP, Action.NAVIGATE_DOWN])

      customSource.stop()
    })
  })
})
