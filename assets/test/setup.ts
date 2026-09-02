/**
 * Global jsdom setup for hook tests.
 *
 * jsdom implements neither `matchMedia` nor the scrolling APIs the hooks call.
 * Install inert versions so a hook can mount without every test stubbing them;
 * tests that care about a value (reduced motion, scroll offsets) override it.
 *
 * These are plain functions on purpose: `vi.spyOn(instance, "scrollIntoView")`
 * returns the prototype's mock unchanged if it already is one, so a `vi.fn()`
 * here would be shared by every element in every test.
 */
import { setReducedMotion } from "./support/media"

setReducedMotion(false)

Element.prototype.scrollIntoView = () => {}
Element.prototype.scrollBy = () => {}
