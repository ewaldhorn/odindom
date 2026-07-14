// Package dom provides a basic DOM manipulation wrapper over a JS handle-table bridge.
package dom

import "core:strconv"

// ------------------------------------------------------------------------------------------------
// Handle represents a reference to a live JS object in the browser, stored in the JS-side
// handle table and addressed by integer id. 0 is null/invalid.
Handle :: distinct u32

// ------------------------------------------------------------------------------------------------
INVALID :: Handle(0)

// ------------------------------------------------------------------------------------------------
// Global element references (set by init()).
document: Handle = INVALID
body: Handle = INVALID
head: Handle = INVALID

// ------------------------------------------------------------------------------------------------
// Scratch buffer for receiving strings back from JS (e.g. property values).
// Single global is safe in WASM — everything runs on one thread.
@(private)
scratch: [4096]u8

// ------------------------------------------------------------------------------------------------
// Imported JS functions (provided by odindom.js).
// ------------------------------------------------------------------------------------------------

foreign import odindom_env "odindom_env"

@(default_calling_convention = "contextless")
foreign odindom_env {
	dom_get_global          :: proc(name: string) -> Handle ---
	dom_get_property        :: proc(elem: Handle, key: string) -> Handle ---

	dom_create_element      :: proc(tag: string) -> Handle ---
	dom_append_child        :: proc(parent, child: Handle) ---
	dom_remove_all_children :: proc(elem: Handle) ---
	dom_set_inner_text      :: proc(elem: Handle, text: string) ---
	dom_set_inner_html      :: proc(elem: Handle, html: string) ---
	dom_set_property_str    :: proc(elem: Handle, key, value: string) ---
	dom_get_property_str    :: proc(elem: Handle, key: string, buf: []byte) -> int ---
	dom_set_class_name      :: proc(elem: Handle, class_name: string) ---
	dom_class_list_add      :: proc(elem: Handle, class_name: string) ---
	dom_class_list_remove   :: proc(elem: Handle, class_name: string) ---
	dom_set_display         :: proc(elem: Handle, display: string) ---
	dom_set_style           :: proc(elem: Handle, prop, value: string) ---
	dom_call_focus          :: proc(elem: Handle) ---
	dom_get_element_by_id   :: proc(id: string) -> Handle ---
	dom_add_style_element   :: proc(css: string) ---
	dom_add_event_listener  :: proc(elem: Handle, event: string, cb_id: u32) ---
	dom_log                 :: proc(msg: string) ---
	dom_alert                :: proc(msg: string) ---
	dom_now                 :: proc() -> f64 ---

	// Generic method-call / numeric-property bridge — lets callers reach JS APIs that dom.odin
	// has no dedicated wrapper for (Web Audio nodes, getBoundingClientRect, preventDefault, ...)
	// without adding a bespoke foreign proc per method.
	dom_call_method0    :: proc(elem: Handle, name: string) ---
	dom_call_method_ret :: proc(elem: Handle, name: string) -> Handle ---
	dom_call_method1f   :: proc(elem: Handle, name: string, a: f64) ---
	dom_call_method2f   :: proc(elem: Handle, name: string, a, b: f64) ---
	dom_call_method1h   :: proc(elem: Handle, name: string, arg: Handle) ---
	dom_set_property_f64 :: proc(elem: Handle, key: string, value: f64) ---

	// Web Audio: AudioContext construction needs the vendor-prefix fallback dance
	// (AudioContext / webkitAudioContext), so it gets its own constructor rather than a generic
	// "new" bridge.
	dom_new_audio_context :: proc() -> Handle ---

	// localStorage
	dom_local_storage_get_item :: proc(key: string, buf: []byte) -> int ---
	dom_local_storage_set_item :: proc(key, value: string) ---
}

// ------------------------------------------------------------------------------------------------
// now returns milliseconds since page load (performance.now()), for wall-clock-accurate timing
// (e.g. a sequencer stepping at a fixed BPM regardless of frame rate).
now :: proc "contextless" () -> f64 {
	return dom_now()
}

// ------------------------------------------------------------------------------------------------
// Lifecycle
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
// init captures global JS references from the browser. Must be called once before anything else.
init :: proc "contextless" () {
	document = dom_get_global("document")
	body = dom_get_property(document, "body")
	head = dom_get_property(document, "head")
}

// ------------------------------------------------------------------------------------------------
// is_valid checks if the handle is non-null.
is_valid :: proc "contextless" (h: Handle) -> bool {
	return h != INVALID
}

// get_property retrieves a handle to a property value of any JS type (object, DOM node, nested
// field, array element by numeric-string index, ...). Use dom.get for a property's string form.
get_property :: proc "contextless" (h: Handle, key: string) -> Handle {
	return dom_get_property(h, key)
}

// ------------------------------------------------------------------------------------------------
// get retrieves a string property from an element by handle.
//
// WARNING: the returned string points at a shared global scratch buffer — copy it if you need
// to retain the value across another call to get/get_string.
get :: proc "contextless" (h: Handle, key: string) -> string {
	n := dom_get_property_str(h, key, scratch[:])
	if n > len(scratch) {
		n = len(scratch)
	}
	return string(scratch[:n])
}

// ------------------------------------------------------------------------------------------------
// set sets a string property on an element by handle.
set :: proc "contextless" (h: Handle, key, value: string) {
	dom_set_property_str(h, key, value)
}

// ------------------------------------------------------------------------------------------------
// set_style sets a single inline CSS property (element.style[prop] = value) by handle.
set_style :: proc "contextless" (h: Handle, prop, value: string) {
	dom_set_style(h, prop, value)
}

// ------------------------------------------------------------------------------------------------
// set_inner_text sets the inner text of an element.
set_inner_text :: proc "contextless" (h: Handle, text: string) {
	dom_set_inner_text(h, text)
}

// ------------------------------------------------------------------------------------------------
// set_inner_html sets the inner HTML of an element.
set_inner_html :: proc "contextless" (h: Handle, html: string) {
	dom_set_inner_html(h, html)
}

// ------------------------------------------------------------------------------------------------
// add_class_to adds a CSS class to the element.
add_class_to :: proc "contextless" (h: Handle, class: string) {
	dom_class_list_add(h, class)
}

// ------------------------------------------------------------------------------------------------
// remove_class_from removes a CSS class from the element.
remove_class_from :: proc "contextless" (h: Handle, class: string) {
	dom_class_list_remove(h, class)
}

// ------------------------------------------------------------------------------------------------
// replace_classes replaces all classes on the element with the given list.
replace_classes :: proc "contextless" (h: Handle, classes: []string) {
	dom_set_class_name(h, "")
	for class in classes {
		dom_class_list_add(h, class)
	}
}

// ================================================================================================
// Element CRUD
// ================================================================================================

// ------------------------------------------------------------------------------------------------
// create_element creates a new HTML element of the given tag name.
create_element :: proc "contextless" (tag: string) -> Handle {
	return dom_create_element(tag)
}

// ------------------------------------------------------------------------------------------------
create_div :: proc "contextless" () -> Handle {
	return create_element("div")
}

// ------------------------------------------------------------------------------------------------
create_paragraph :: proc "contextless" () -> Handle {
	return create_element("p")
}

// ------------------------------------------------------------------------------------------------
create_paragraph_with_text :: proc "contextless" (text: string) -> Handle {
	p := create_element("p")
	set_inner_text(p, text)
	return p
}

// ------------------------------------------------------------------------------------------------
create_button :: proc "contextless" (text: string) -> Handle {
	b := create_element("button")
	set(b, "type", "button")
	set_inner_text(b, text)
	return b
}

// ------------------------------------------------------------------------------------------------
create_img :: proc "contextless" (src: string) -> Handle {
	img := create_element("img")
	set(img, "src", src)
	return img
}

// ------------------------------------------------------------------------------------------------
// add_element_to appends a child element to a target element.
add_element_to :: proc "contextless" (target, elem: Handle) {
	dom_append_child(target, elem)
}

// ------------------------------------------------------------------------------------------------
// add_to_body appends a child element to the document body.
add_to_body :: proc "contextless" (elem: Handle) {
	add_element_to(body, elem)
}

// ------------------------------------------------------------------------------------------------
// remove_all_child_elements_from removes all children from the target element.
remove_all_child_elements_from :: proc "contextless" (target: Handle) {
	dom_remove_all_children(target)
}

// ------------------------------------------------------------------------------------------------
// get_element_by_id returns the element handle matching the specified ID, or INVALID.
get_element_by_id :: proc "contextless" (id: string) -> Handle {
	return dom_get_element_by_id(id)
}

// ------------------------------------------------------------------------------------------------
// wrap_element_with_new_div wraps an existing element in a new div with the given classes.
wrap_element_with_new_div :: proc "contextless" (element: Handle, classes: []string) -> Handle {
	div := create_div()
	for class in classes {
		add_class_to(div, class)
	}
	add_element_to(div, element)
	return div
}

// ================================================================================================
// Visibility
// ================================================================================================

// ------------------------------------------------------------------------------------------------
// hide sets display to "none" on the element matching the ID.
hide :: proc "contextless" (id: string) {
	elem := get_element_by_id(id)
	if is_valid(elem) {
		dom_set_display(elem, "none")
	}
}

// ------------------------------------------------------------------------------------------------
// show sets display to "block" on the element matching the ID.
show :: proc "contextless" (id: string) {
	elem := get_element_by_id(id)
	if is_valid(elem) {
		dom_set_display(elem, "block")
	}
}

// ------------------------------------------------------------------------------------------------
// set_focus calls focus() on the element matching the ID.
set_focus :: proc "contextless" (id: string) {
	elem := get_element_by_id(id)
	if is_valid(elem) {
		dom_call_focus(elem)
	}
}

// ================================================================================================
// Property access (string-based, by ID)
// ================================================================================================

// ------------------------------------------------------------------------------------------------
// get_string retrieves a string property from an element by ID.
//
// WARNING: the returned string points at a shared global scratch buffer — copy it if you need
// to retain the value across another call to get/get_string.
get_string :: proc "contextless" (elem_id, key: string) -> string {
	elem := get_element_by_id(elem_id)
	if !is_valid(elem) {
		return ""
	}
	return get(elem, key)
}

// ------------------------------------------------------------------------------------------------
// set_value sets a string property on an element by ID.
set_value :: proc "contextless" (elem_id, key, value: string) {
	elem := get_element_by_id(elem_id)
	if is_valid(elem) {
		set(elem, key, value)
	}
}

// ================================================================================================
// Style (by element ID)
// ================================================================================================

// ------------------------------------------------------------------------------------------------
// add_class adds a CSS class to the element looked up by ID.
add_class :: proc "contextless" (elem_id, class: string) {
	elem := get_element_by_id(elem_id)
	if is_valid(elem) {
		add_class_to(elem, class)
	}
}

// ------------------------------------------------------------------------------------------------
// remove_class removes a CSS class from the element looked up by ID.
remove_class :: proc "contextless" (elem_id, class: string) {
	elem := get_element_by_id(elem_id)
	if is_valid(elem) {
		remove_class_from(elem, class)
	}
}

// ------------------------------------------------------------------------------------------------
// add_new_style_element injects a style block with raw CSS rules into document head.
add_new_style_element :: proc "contextless" (css: string) {
	dom_add_style_element(css)
}

// ================================================================================================
// Events
// ================================================================================================

// ------------------------------------------------------------------------------------------------
// add_event_listener registers an event listener on the element. cb_id identifies the callback
// to the host app's odindom_invoke_callback dispatcher (see README for the calling convention).
add_event_listener :: proc "contextless" (elem: Handle, event: string, cb_id: u32) {
	dom_add_event_listener(elem, event, cb_id)
}

// ------------------------------------------------------------------------------------------------
// add_event_listener_by_id registers an event listener on the element matching the ID.
add_event_listener_by_id :: proc "contextless" (id, event: string, cb_id: u32) {
	elem := get_element_by_id(id)
	if is_valid(elem) {
		add_event_listener(elem, event, cb_id)
	}
}

// ------------------------------------------------------------------------------------------------
// last_event holds a handle to the raw JS Event object for the callback currently being
// dispatched. odindom.js calls odindom_set_last_event() immediately before invoking a listener's
// callback, so within odindom_invoke_callback you can read event fields via
// dom.get(dom.last_event(), "offsetX") etc. (Get returns the JS value's string form — parse
// numeric fields with core:strconv.)
@(private)
last_event: Handle = INVALID

// ------------------------------------------------------------------------------------------------
last_event_handle :: proc "contextless" () -> Handle {
	return last_event
}

// ------------------------------------------------------------------------------------------------
@(export)
odindom_set_last_event :: proc "contextless" (h: Handle) {
	last_event = h
}

// ================================================================================================
// Generic method-call / numeric-property bridge
// ================================================================================================

// ------------------------------------------------------------------------------------------------
// call_method calls a zero-argument, no-return-value method on the element (e.g. "preventDefault",
// "resume", "stopPropagation").
call_method :: proc "contextless" (h: Handle, name: string) {
	dom_call_method0(h, name)
}

// ------------------------------------------------------------------------------------------------
// call_method_ret calls a zero-argument method that returns a JS object, and returns a handle to
// it (e.g. "getBoundingClientRect", "createOscillator", "createGain").
call_method_ret :: proc "contextless" (h: Handle, name: string) -> Handle {
	return dom_call_method_ret(h, name)
}

// ------------------------------------------------------------------------------------------------
// call_method1f calls a method taking a single float64 argument and discards the return value
// (e.g. AudioScheduledSourceNode "start"/"stop" with a timestamp).
call_method1f :: proc "contextless" (h: Handle, name: string, a: f64) {
	dom_call_method1f(h, name, a)
}

// ------------------------------------------------------------------------------------------------
// call_method2f calls a method taking two float64 arguments and discards the return value (e.g.
// AudioParam "setValueAtTime"/"linearRampToValueAtTime"/"exponentialRampToValueAtTime").
call_method2f :: proc "contextless" (h: Handle, name: string, a, b: f64) {
	dom_call_method2f(h, name, a, b)
}

// ------------------------------------------------------------------------------------------------
// call_method1h calls a method taking a single handle argument (e.g. AudioNode "connect").
call_method1h :: proc "contextless" (h: Handle, name: string, arg: Handle) {
	dom_call_method1h(h, name, arg)
}

// ------------------------------------------------------------------------------------------------
// set_property_f64 sets a numeric property on the element (e.g. an AudioParam's "value").
set_property_f64 :: proc "contextless" (h: Handle, key: string, value: f64) {
	dom_set_property_f64(h, key, value)
}

// ------------------------------------------------------------------------------------------------
// get_f64 retrieves a numeric property from an element, parsed from its string form.
get_f64 :: proc (h: Handle, key: string) -> f64 {
	v, _ := strconv.parse_f64(get(h, key))
	return v
}

// ------------------------------------------------------------------------------------------------
// new_audio_context constructs a Web Audio AudioContext (falling back to webkitAudioContext on
// older Safari). Returns INVALID if the browser has neither.
new_audio_context :: proc "contextless" () -> Handle {
	return dom_new_audio_context()
}

// ================================================================================================
// localStorage
// ================================================================================================

// ------------------------------------------------------------------------------------------------
// local_storage_get_item returns the string stored under key, or ok=false if unset.
//
// WARNING: the returned string points at a shared global scratch buffer — copy it if you need to
// retain the value past another call to get/get_string/local_storage_get_item.
local_storage_get_item :: proc "contextless" (key: string) -> (value: string, ok: bool) {
	n := dom_local_storage_get_item(key, scratch[:])
	if n < 0 {
		return "", false
	}
	if n > len(scratch) {
		n = len(scratch)
	}
	return string(scratch[:n]), true
}

// ------------------------------------------------------------------------------------------------
// local_storage_set_item stores value under key.
local_storage_set_item :: proc "contextless" (key, value: string) {
	dom_local_storage_set_item(key, value)
}

// ================================================================================================
// Logging
// ================================================================================================

// ------------------------------------------------------------------------------------------------
// log logs a message to the browser developer console.
log :: proc "contextless" (msg: string) {
	dom_log(msg)
}

// ------------------------------------------------------------------------------------------------
// alert triggers a browser modal dialog with the specified message.
alert :: proc "contextless" (msg: string) {
	dom_alert(msg)
}
