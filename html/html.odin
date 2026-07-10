// Package html provides declarative HTML tag builder constructors and utility procedures.
//
// Odin has no method-call chaining (no UFCS, no methods-on-types), so unlike GoDOM/ZigDOM's
// fluent `.Class(x).Text(y)` style, every builder procedure here takes a dom.Handle and returns
// the same dom.Handle, so calls compose either as sequential statements or as nested calls:
//
//	p := html.p()
//	html.set_id(p, "greeting")
//	html.text(p, "Hello")
//	html.append_to(p, parent)
//
//	// or, nested:
//	html.append_to(html.text(html.set_id(html.p(), "greeting"), "Hello"), parent)
package html

import "../dom"

// ------------------------------------------------------------------------------------------------
// Elm is an alias for dom.Handle, used purely for documentation clarity in signatures below.
Elm :: dom.Handle

// ------------------------------------------------------------------------------------------------
// init creates a new element for the specified HTML tag.
init :: proc "contextless" (tag: string) -> Elm {
	return dom.create_element(tag)
}

// ------------------------------------------------------------------------------------------------
// set_id sets the element's DOM id attribute.
set_id :: proc "contextless" (e: Elm, val: string) -> Elm {
	dom.set(e, "id", val)
	return e
}

// ------------------------------------------------------------------------------------------------
// class adds a class name to the element.
class :: proc "contextless" (e: Elm, val: string) -> Elm {
	dom.add_class_to(e, val)
	return e
}

// ------------------------------------------------------------------------------------------------
// text sets the inner text of the element.
text :: proc "contextless" (e: Elm, val: string) -> Elm {
	dom.set_inner_text(e, val)
	return e
}

// ------------------------------------------------------------------------------------------------
// set_html sets the inner HTML content of the element.
set_html :: proc "contextless" (e: Elm, val: string) -> Elm {
	dom.set_inner_html(e, val)
	return e
}

// ------------------------------------------------------------------------------------------------
// attr sets an arbitrary string attribute.
attr :: proc "contextless" (e: Elm, key, val: string) -> Elm {
	dom.set(e, key, val)
	return e
}

// ------------------------------------------------------------------------------------------------
// child appends another element as a child.
child :: proc "contextless" (e: Elm, child_elem: Elm) -> Elm {
	dom.add_element_to(e, child_elem)
	return e
}

// ------------------------------------------------------------------------------------------------
// append_to appends this element under a parent element.
append_to :: proc "contextless" (e: Elm, parent: Elm) -> Elm {
	dom.add_element_to(parent, e)
	return e
}

// ------------------------------------------------------------------------------------------------
// on registers an event listener callback on the element.
on :: proc "contextless" (e: Elm, event: string, cb_id: u32) -> Elm {
	dom.add_event_listener(e, event, cb_id)
	return e
}

// ------------------------------------------------------------------------------------------------
// build returns the underlying handle. Provided for API-parity/readability with GoDOM/ZigDOM;
// e itself is already the handle.
build :: proc "contextless" (e: Elm) -> dom.Handle {
	return e
}

// ================================================================================================
// Tag constructors
// ================================================================================================

// ------------------------------------------------------------------------------------------------
// Structural tags
div    :: proc "contextless" () -> Elm { return init("div") }
span   :: proc "contextless" () -> Elm { return init("span") }
p      :: proc "contextless" () -> Elm { return init("p") }
button :: proc "contextless" () -> Elm { return init("button") }
a      :: proc "contextless" () -> Elm { return init("a") }

// ------------------------------------------------------------------------------------------------
// Headings
h1 :: proc "contextless" () -> Elm { return init("h1") }
h2 :: proc "contextless" () -> Elm { return init("h2") }
h3 :: proc "contextless" () -> Elm { return init("h3") }
h4 :: proc "contextless" () -> Elm { return init("h4") }
h5 :: proc "contextless" () -> Elm { return init("h5") }
h6 :: proc "contextless" () -> Elm { return init("h6") }

// ------------------------------------------------------------------------------------------------
// Semantic layout
article :: proc "contextless" () -> Elm { return init("article") }
aside   :: proc "contextless" () -> Elm { return init("aside") }
section :: proc "contextless" () -> Elm { return init("section") }
nav     :: proc "contextless" () -> Elm { return init("nav") }
header  :: proc "contextless" () -> Elm { return init("header") }
footer  :: proc "contextless" () -> Elm { return init("footer") }
main    :: proc "contextless" () -> Elm { return init("main") }

// ------------------------------------------------------------------------------------------------
// Lists
ul :: proc "contextless" () -> Elm { return init("ul") }
ol :: proc "contextless" () -> Elm { return init("ol") }
li :: proc "contextless" () -> Elm { return init("li") }
dl :: proc "contextless" () -> Elm { return init("dl") }
dt :: proc "contextless" () -> Elm { return init("dt") }
dd :: proc "contextless" () -> Elm { return init("dd") }

// ------------------------------------------------------------------------------------------------
// Inline formatting
strong :: proc "contextless" () -> Elm { return init("strong") }
em     :: proc "contextless" () -> Elm { return init("em") }
code   :: proc "contextless" () -> Elm { return init("code") }
pre    :: proc "contextless" () -> Elm { return init("pre") }
small  :: proc "contextless" () -> Elm { return init("small") }
mark   :: proc "contextless" () -> Elm { return init("mark") }
b      :: proc "contextless" () -> Elm { return init("b") }
i      :: proc "contextless" () -> Elm { return init("i") }

// ------------------------------------------------------------------------------------------------
// Form elements
form     :: proc "contextless" () -> Elm { return init("form") }
input    :: proc "contextless" () -> Elm { return init("input") }
label    :: proc "contextless" () -> Elm { return init("label") }
select   :: proc "contextless" () -> Elm { return init("select") }
option   :: proc "contextless" () -> Elm { return init("option") }
textarea :: proc "contextless" () -> Elm { return init("textarea") }
fieldset :: proc "contextless" () -> Elm { return init("fieldset") }
legend   :: proc "contextless" () -> Elm { return init("legend") }

// ------------------------------------------------------------------------------------------------
// Media / void elements
img :: proc "contextless" () -> Elm { return init("img") }
br  :: proc "contextless" () -> Elm { return init("br") }
hr  :: proc "contextless" () -> Elm { return init("hr") }

// ------------------------------------------------------------------------------------------------
// Tables
table :: proc "contextless" () -> Elm { return init("table") }
thead :: proc "contextless" () -> Elm { return init("thead") }
tbody :: proc "contextless" () -> Elm { return init("tbody") }
tr    :: proc "contextless" () -> Elm { return init("tr") }
th    :: proc "contextless" () -> Elm { return init("th") }
td    :: proc "contextless" () -> Elm { return init("td") }

// ------------------------------------------------------------------------------------------------
// Miscellaneous
figure     :: proc "contextless" () -> Elm { return init("figure") }
figcaption :: proc "contextless" () -> Elm { return init("figcaption") }
details    :: proc "contextless" () -> Elm { return init("details") }
summary    :: proc "contextless" () -> Elm { return init("summary") }
blockquote :: proc "contextless" () -> Elm { return init("blockquote") }
cite       :: proc "contextless" () -> Elm { return init("cite") }
time       :: proc "contextless" () -> Elm { return init("time") }
