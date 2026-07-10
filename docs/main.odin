// OdinDOM demo — a full port of GoDOM's demo/demo.go (and ZigDOM's demo/src/demo.zig, which
// blazed the "port this specific demo to a language with no closures/GC" trail this follows).
//
// Three canvases: a static synthwave gallery (canvas_one.odin), an animated ball-physics
// simulation with switchable gravity (canvas_two.odin), and a retro drum machine sequencer
// (canvas_three.odin). Plus DOM/html builder showcases (this file) and a pre-rendered UI click
// sound played back through Web Audio (app.js).
package main

import "base:runtime"
import "core:fmt"
import "../canvas"
import "../colour"
import "../dom"
import "../html"
import "../sound"

// ------------------------------------------------------------------------------------------------
// Resources & Constants
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
BODY_STYLE :: #load("bodystyle.css", string)
DOMMIE_TEXT :: #load("odindom.txt", string)

VERSION :: "0.0.1"
NAME :: "OdinDOM Demo"

// ------------------------------------------------------------------------------------------------
// Application State
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
is_ready:              bool
boo_counter:            u32
application_container: dom.Handle = dom.INVALID
article_element:        dom.Handle = dom.INVALID
aside_element:          dom.Handle = dom.INVALID
canvas_one_time:        u32
grid_offset:            f64

// ------------------------------------------------------------------------------------------------
// Click sound buffer — pre-rendered 50ms UI click (2205 samples at 44.1kHz)
click_buffer: [2205]f32

// ------------------------------------------------------------------------------------------------
// CSS class / size options for aside element generators
css_colours := []string{"red", "blue", "orange"}
css_sizes   := []string{"large", "larger", "xlarge"}

// ------------------------------------------------------------------------------------------------
// Random text pools for aside content
facts := []string{
	"WASM runs at near-native speed.",
	"Odin has no hidden control flow, and no exceptions.",
	"First website: info.cern.ch (1991).",
	"Odin has first-class SOA and array-of-structs support.",
	"A kilobyte of RAM cost ~$3M in 1957.",
	"The first computer bug was a real moth.",
}
quips := []string{
	"Stay awhile and listen.",
	"All these worlds are yours.",
	"It was a pleasure to burn.",
	"The sky above the port…",
	"So long, and thanks for all the fish.",
	"I'm sorry, Dave.",
}
tags := []string{
	"odin",
	"wasm",
	"no-gc",
	"handle-table",
	"retro",
	"synthwave",
}

// ------------------------------------------------------------------------------------------------
// Demo-local PRNG (xorshift64) — independent of colour package's PRNG. Used for UI randomisation
// and to cross-seed colour.seed() before each canvas redraw, so each refresh looks unique.
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
rng_state: u64 = 42

// ------------------------------------------------------------------------------------------------
next_random :: proc "contextless" () -> u32 {
	rng_state ~= rng_state << 13
	rng_state ~= rng_state >> 7
	rng_state ~= rng_state << 17
	return u32(rng_state)
}

// ------------------------------------------------------------------------------------------------
random_css_colour :: proc "contextless" () -> string {
	return css_colours[next_random() % u32(len(css_colours))]
}

// ------------------------------------------------------------------------------------------------
random_css_size :: proc "contextless" () -> string {
	return css_sizes[next_random() % u32(len(css_sizes))]
}

// ------------------------------------------------------------------------------------------------
// Interaction coordinates — written by JS (odindom_set_interaction) before invoking the callback
// for a canvas click/touch. Reset to -1 after each impulse so spurious re-fires are no-ops.
// odindom.js's generic dom.last_event_handle() offsetX/offsetY isn't used here because canvas
// two/three are displayed at a CSS-scaled size (`max-width: 100%`) — mapping CSS pixels to canvas
// pixel-buffer space requires the caller to know the canvas's bounding rect, which app.js does.
// ------------------------------------------------------------------------------------------------
interact_x: i32 = -1
interact_y: i32 = -1

// ------------------------------------------------------------------------------------------------
@(export)
odindom_set_interaction :: proc "c" (x, y: i32) {
	interact_x = x
	interact_y = y
}

// ------------------------------------------------------------------------------------------------
// Callback dispatch
// ------------------------------------------------------------------------------------------------

// Callback table: 0 add something, 1 clear aside, 2 refresh canvas one, 3 animation tick,
// 4 canvas two interaction, 5 article handle demo, 6 drum pad click, 7 drum play/pause,
// 8 cycle gravity.
CB_ADD_SOMETHING      :: 0
CB_CLEAR_ASIDE        :: 1
CB_REFRESH_CANVAS_ONE :: 2
CB_ANIMATION_TICK     :: 3
CB_CANVAS_INTERACTION :: 4
CB_ARTICLE_DEMO       :: 5
CB_DRUM_CANVAS_CLICK  :: 6
CB_DRUM_PLAY_PAUSE    :: 7
CB_CYCLE_GRAVITY      :: 8

// ------------------------------------------------------------------------------------------------
@(export)
odindom_invoke_callback :: proc "c" (id: u32) {
	context = runtime.default_context()
	switch id {
	case CB_ADD_SOMETHING:
		on_add_something_click()
	case CB_CLEAR_ASIDE:
		on_clear_aside_click()
	case CB_REFRESH_CANVAS_ONE:
		on_refresh_canvas_one_click()
	case CB_ANIMATION_TICK:
		on_animation_tick()
	case CB_CANVAS_INTERACTION:
		on_canvas_interaction()
	case CB_ARTICLE_DEMO:
		dom.log("Handle-based event listener fired on article element.")
	case CB_DRUM_CANVAS_CLICK:
		on_drum_canvas_click()
	case CB_DRUM_PLAY_PAUSE:
		on_drum_play_pause()
	case CB_CYCLE_GRAVITY:
		on_cycle_gravity()
	}
}

// ------------------------------------------------------------------------------------------------
on_add_something_click :: proc() {
	if !is_ready {
		return
	}
	switch next_random() % 5 {
	case 0:
		add_boo()
	case 1:
		add_random_paragraph()
	case 2:
		add_aside_note()
	case 3:
		add_aside_tag()
	case 4:
		add_aside_quip()
	case:
		add_boo()
	}
}

// ------------------------------------------------------------------------------------------------
on_clear_aside_click :: proc() {
	if !is_ready {
		return
	}
	dom.remove_class_from(aside_element, "showcase-active")
	dom.remove_all_child_elements_from(aside_element)
	dom.set_focus("addSomethingButton")
}

// ------------------------------------------------------------------------------------------------
on_refresh_canvas_one_click :: proc() {
	if !is_ready {
		return
	}
	current_theme_idx = (current_theme_idx + 1) % len(themes)
}

// ------------------------------------------------------------------------------------------------
on_animation_tick :: proc() {
	if !is_ready {
		return
	}
	canvas_one_time += 1
	grid_offset += 0.025
	if grid_offset >= 1.0 {
		grid_offset -= 1.0
	}

	perform_demo_on_canvas_one()
	update_canvas_two()
	perform_demo_on_canvas_three()
}

// ------------------------------------------------------------------------------------------------
// DOM helpers
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
add_boo :: proc() {
	boo_counter += 1
	text_buf, id_buf: [32]u8
	text := fmt.bprintf(text_buf[:], "Boo! (%d)", boo_counter)
	id := fmt.bprintf(id_buf[:], "boo-%d", boo_counter)

	p := html.p()
	html.set_id(p, id)
	html.attr(p, "data-count", text)
	html.text(p, text)
	html.append_to(p, aside_element)
}

// ------------------------------------------------------------------------------------------------
add_random_paragraph :: proc() {
	inner := html.p()
	html.set_id(inner, "random-p")
	html.text(inner, "This is some text using builder API")

	d := html.div()
	html.class(d, random_css_colour())
	html.class(d, random_css_size())
	html.attr(d, "data-random", "yes")
	html.child(d, inner)
	html.append_to(d, aside_element)
}

// ------------------------------------------------------------------------------------------------
add_aside_note :: proc() {
	idx := next_random() % u32(len(facts))
	id_buf: [16]u8
	id := fmt.bprintf(id_buf[:], "note-%d", boo_counter)

	note := html.div()
	html.class(note, "aside-note")
	html.class(note, random_css_colour())
	html.set_id(note, id)
	html.text(note, facts[idx])
	html.append_to(note, aside_element)
}

// ------------------------------------------------------------------------------------------------
add_aside_tag :: proc() {
	idx := next_random() % u32(len(tags))
	id_buf: [16]u8
	id := fmt.bprintf(id_buf[:], "tag-%d", boo_counter)

	tag := html.span()
	html.class(tag, "aside-tag")
	html.class(tag, random_css_colour())
	html.set_id(tag, id)
	html.text(tag, tags[idx])
	html.append_to(tag, aside_element)

	// Also append a space so tags don't stick together.
	spacer := html.span()
	html.text(spacer, " ")
	html.append_to(spacer, aside_element)
}

// ------------------------------------------------------------------------------------------------
add_aside_quip :: proc() {
	idx := next_random() % u32(len(quips))
	id_buf: [16]u8
	id := fmt.bprintf(id_buf[:], "quip-%d", boo_counter)

	q := html.div()
	html.class(q, "aside-quip")
	html.set_id(q, id)
	html.text(q, quips[idx])
	html.append_to(q, aside_element)
}

// ------------------------------------------------------------------------------------------------
toggle_elements :: proc() {
	dom.hide("loading")
	dom.show("controls")
	dom.show("information")
}

// ------------------------------------------------------------------------------------------------
create_app_elements :: proc() {
	a := html.article()
	html.append_to(a, application_container)
	article_element = a

	aside := html.aside()
	html.append_to(aside, application_container)
	aside_element = aside
}

// ------------------------------------------------------------------------------------------------
populate_article_element :: proc() {
	p := html.p()
	html.set_id(p, "dommie-text")
	html.set_html(p, DOMMIE_TEXT)
	html.append_to(p, article_element)
}

// ------------------------------------------------------------------------------------------------
set_title :: proc() {
	buf: [128]u8
	title := fmt.bprintf(buf[:], "%s v%s", NAME, VERSION)
	elem := dom.get_element_by_id("title")
	if dom.is_valid(elem) {
		dom.set_inner_text(elem, title)
	}
}

// ------------------------------------------------------------------------------------------------
// Entry point
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
// Exported entry point — JS calls this once after WASM instantiation.
@(export)
odindom_main :: proc "c" () {
	context = runtime.default_context()

	dom.init()
	dom.log("Ok. OdinDOM is starting. Here we go!")

	toggle_elements()
	set_title()
	dom.add_new_style_element(BODY_STYLE)

	application_container = dom.get_element_by_id("application")
	create_app_elements()
	populate_article_element()

	dom.add_event_listener_by_id("addSomethingButton", "click", CB_ADD_SOMETHING)
	dom.add_event_listener_by_id("clearAsideButton", "click", CB_CLEAR_ASIDE)
	dom.add_event_listener_by_id("refreshButton", "click", CB_REFRESH_CANVAS_ONE)
	dom.add_event_listener_by_id("drumPlayButton", "click", CB_DRUM_PLAY_PAUSE)
	dom.add_event_listener_by_id("gravityButton", "click", CB_CYCLE_GRAVITY)

	canvas_one = canvas.new_canvas(800, 600, canvas_one_buffer[:], "canvasOneDiv")
	canvas_two = canvas.new_canvas(600, 450, canvas_two_buffer[:], "canvasTwoDiv")
	canvas_three = canvas.new_canvas(DRUM_CANVAS_W, DRUM_CANVAS_H, canvas_three_buffer[:], "canvasThreeDiv")

	perform_demo_on_canvas_one()
	init_balls()
	perform_demo_on_canvas_three()
	set_drum_button_text()
	update_gravity_button_text()

	is_ready = true

	// Canvas pixel readback demo.
	if px, ok := canvas.get_pixel(&canvas_one, 0, 0); ok && !colour.is_empty(px) {
		dom.log("Canvas One pixel (0,0): non-empty after render.")
	}

	// DOM ID-based property access demo (set_value + get_string).
	dom.set_value("title", "lang", "en")
	dom.log(fmt.tprintf("dom.get_string() on #title: %s", dom.get_string("title", "lang")))

	// replace_classes demo on title.
	if title_handle := dom.get_element_by_id("title"); dom.is_valid(title_handle) {
		dom.replace_classes(title_handle, []string{"demo-title"})
	}

	// Builder .on() demo.
	btn := html.button()
	html.text(btn, "Builder .on() demo")
	html.on(btn, "click", CB_ADD_SOMETHING)
	html.append_to(btn, application_container)

	// Handle-based API showcase (not using the html builder).
	showcase_heading := dom.create_paragraph_with_text("Handle-based API Showcase")
	dom.add_class_to(showcase_heading, "boo-header")
	dom.add_element_to(aside_element, showcase_heading)

	dom.set(showcase_heading, "title", "Created via handle-based dom.set() API")
	dom.log(fmt.tprintf("dom.get() on showcase heading: %s", dom.get(showcase_heading, "title")))

	// Exercise dom.wrap_element_with_new_div().
	showcase_p := dom.create_paragraph_with_text("This paragraph was wrapped via dom.wrap_element_with_new_div()")
	wrapped := dom.wrap_element_with_new_div(showcase_p, []string{"boo-wrapper"})
	dom.add_element_to(aside_element, wrapped)

	// Exercise add_class_to on the aside element itself.
	dom.add_class_to(aside_element, "showcase-active")

	// Exercise add_event_listener by handle (not by ID).
	dom.add_event_listener(article_element, "click", CB_ARTICLE_DEMO)

	// Pre-render UI click sound into the static buffer for button feedback.
	sound.fill_click(click_buffer[:])

	dom.start_animation_loop(CB_ANIMATION_TICK)
}

// ------------------------------------------------------------------------------------------------
// Sound effect exports — JS retrieves the pre-rendered click buffer for UI button feedback.
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
@(export)
odindom_get_click_buffer_ptr :: proc "c" () -> rawptr {
	return &click_buffer
}

// ------------------------------------------------------------------------------------------------
@(export)
odindom_get_click_buffer_len :: proc "c" () -> i32 {
	return len(click_buffer)
}

// ------------------------------------------------------------------------------------------------
// Drum machine exports — JS can inspect sequencer dimensions and active beats.
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
@(export)
odindom_drum_is_beat_active :: proc "c" (track, step: u32) -> b32 {
	if track >= DRUM_TRACKS || step >= DRUM_STEPS {
		return false
	}
	return b32(drum_pattern[track][step])
}

// ------------------------------------------------------------------------------------------------
@(export)
odindom_drum_get_track_count :: proc "c" () -> u32 {
	return DRUM_TRACKS
}

// ------------------------------------------------------------------------------------------------
@(export)
odindom_drum_get_step_count :: proc "c" () -> u32 {
	return DRUM_STEPS
}
