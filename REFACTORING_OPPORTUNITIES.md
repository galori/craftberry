# Refactoring opportunities

Running notes on abstractions that would have prevented a bug we actually hit, or that would
prevent one we can see coming. Each entry says what exists today, what it should be, and — where
applicable — the concrete failure that motivated it, so a future reader can judge whether the
abstraction still earns its keep.

Entries are removed when done, not ticked off.

## Device E2E harness

### 1. Hotbar slot numbers — DONE (2026-08-06)

`MinecraftCalibratedLayout.hotbarSlot(_:)` now derives slot 1...9 from a measured row centre and
pitch, and every recipe's `outputDestination` is expressed as a named slot.

Motivating failure: each recipe carried a hand-measured `MinecraftCoordinate` for the slot its
output lands in. Closing the crafting table returns the finished recipe's part-used ingredient
stacks to the hotbar, so the next recipe's output lands in slot 6, not slot 2. The hardcoded
coordinate tapped slot 2, raised a "Redstone Dust" tooltip, and the run failed its item-name
assertion three steps downstream of the actual mistake.

Left undone: which slot a recipe lands in is still asserted by a human reading the plan
(`firstCraftSlot` / `slotAfterIngredientsReturn`). The compiler could *track* hotbar occupancy as
it compiles a plan and assign the slot itself — it already knows how many ingredient stacks each
recipe uses and whether the table resets. That would make the two named constants unnecessary and
close the last hand-reasoned step.

### 2. Screenshot ↔ config coordinate transform

Every calibration this session went through the same undocumented arithmetic, done by hand in an
ad-hoc Python snippet each time: Minecraft renders landscape inside a portrait screen buffer, so
`config_x = shot_y_norm` and `config_y = 1 - shot_x_norm` — *except* when the device settles in the
opposite landscape orientation, when it is the 180° rotation of that.

There should be one tested helper (`MinecraftScreenGeometry`?) converting between a point in a
captured screenshot and a config coordinate, taking the orientation as an argument. It is pure
arithmetic and trivially unit-testable on the simulator. Doing it by hand each time is how
`closeCraftingTable` and `craftingOutput` both ended up a handful of pixels inside their button's
edge — see item 3.

### 3. Calibrating to a measured *centre*, not a point that happens to work

`closeCraftingTable` and `craftingOutput` were both calibrated to coordinates that sat ~6-9 pixels
inside their target's edge. Both worked on the device they were calibrated on and on the first of
two identical taps on the new one, then missed — producing failures that surfaced far downstream
(a crafting table that never closed; a finished item left sitting in the output slot while the run
continued as though it had been collected).

Wanted: a calibration helper that takes a screenshot and a target's colour signature, finds the
element's bounding box, and emits its centre — plus a debug assertion mode that reports how close
each configured tap sits to the edge of the thing it is supposed to hit. Most of this session's
grinding was rediscovering, one screenshot at a time, that a coordinate was marginal rather than
wrong.

### 4. Orientation-independent pixel assertions — OPEN BUG

`MinecraftOCRInspector` now tries all four orientations, but `MinecraftPixelInspector` still reads
fixed normalized ranges straight off the raw buffer (`.redstonePickaxeOutput` at x 0.18...0.31,
y 0.67...0.75). In the flipped landscape orientation it will sample the wrong region and silently
report a mismatch.

This is a live bug, not a hypothetical: it is only unexercised because the sole pixel assertion
belongs to `redstoneToolSet`, which has not run on this device since the orientation flip was
discovered. It should share the layout's coordinate space and the same orientation handling as OCR
rather than carrying its own raw ranges.

### 5. Crafting grid slots — mostly done, one gap

`MinecraftCalibratedLayout.craftingSlot(_:)` already derives all nine slots from a top-left origin
and a row/column step, which is why the grid needed no recalibration for the iPhone 13 Pro when
almost everything around it did. This is the model the other coordinates should follow.

The gap: `creativeResult(column:)` covers only the first row (`precondition(1...4)`). Any recipe
whose ingredient search returns a result outside the first four columns cannot be expressed, and
would need a second hand-calibrated constant.

### 6. Step-level failure context

Failures report the assertion that fired, which is routinely several steps after the mistake — a
missed close-button tap surfaced as "OCR did not find 'Redstone Boots'". Screenshots are attached
per step, but reading them means exporting the result bundle and rotating images by hand.

Wanted: cheap invariant checks between steps (is the crafting table actually open? is the grid
empty when a recipe starts?) so a run fails at the step that broke. The compiler already knows
enough to insert them — `resetCraftingTableSteps()` asserts "Crafting" is on screen after
reopening, which is exactly the right idea but too weak, since that text is present whether or not
the close ever happened.

### 7. Result-bundle screenshot extraction

Every diagnosis this session repeated the same sequence by hand: find the newest `.xcresult`,
`xcrun xcresulttool export attachments` with a test-id whose exact form is easy to get wrong (no
target prefix, trailing `()`), parse `manifest.json` to map human-readable names to exported
filenames, then rotate the PNG to be readable.

This should be a script (`scripts/e2e-screenshots.sh <step-name-substring>`). It is perhaps twenty
lines and would have saved a dozen manual round-trips.

## Known-stale calibration

`MinecraftDeviceE2EConfig.json` and `MinecraftCalibratedLayout` were previously shared by
two physical devices running different Minecraft versions (iPhone 16e / 26.33, iPhone 13 Pro /
26.40). The project has now migrated to the iPhone 13 Pro as the sole dedicated device; the 16e is
retired. If a second device is reintroduced, calibration should be per-device — keyed by model —
rather than one set of constants edited in place.
