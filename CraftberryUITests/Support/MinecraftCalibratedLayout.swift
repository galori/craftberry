import CoreGraphics

struct MinecraftCalibratedLayout {
    let creativeSearchField = MinecraftCoordinate(x: 0.29, y: 0.155)
    let creativeSearchClearButton = MinecraftCoordinate(x: 0.463, y: 0.155)
    // Measured centre of the output slot, whose plate spans x 0.673...0.724 and y 0.651...0.762.
    // The previous y of 0.756 sat about six pixels inside the slot's edge: it took the first
    // recipe's output and then missed the second's, leaving the finished item sitting in the slot
    // while the run carried on as though it had been collected.
    let craftingOutput = MinecraftCoordinate(x: 0.6981, y: 0.7064)
    // Measured centre of the close button, whose plate spans x 0.896...0.951 and y 0.022...0.120.
    // The previous 0.947 sat about nine pixels inside the right edge and missed intermittently —
    // confirmed live, where the tap left the crafting table open and so left the finished recipe's
    // leftover stacks in the grid, corrupting the next recipe rather than failing outright.
    let closeCraftingTable = MinecraftCoordinate(x: 0.9232, y: 0.0709)
    let reopenCraftingTable = MinecraftCoordinate(x: 0.5075, y: 0.265)

    /// A hotbar slot, numbered 1...9 from the left.
    ///
    /// Taking a crafting output drops it into the lowest-numbered free slot, and Minecraft renders
    /// an item's name only in the tooltip raised by tapping the slot it landed in — so a recipe has
    /// to know its slot exactly. Hand-computing those coordinates per recipe is what produced the
    /// bug this replaces: a stack of leftover ingredients returned to the hotbar on the table
    /// close, the assumed slot was two places off, and the tap raised a "Redstone Dust" tooltip
    /// instead of the crafted item's. Row centre and a 0.0555 pitch — the same step the crafting
    /// grid's columns use — are both measured off a device screenshot.
    func hotbarSlot(_ slot: Int) -> MinecraftCoordinate {
        precondition((1...9).contains(slot), "Minecraft's hotbar has nine slots.")
        return MinecraftCoordinate(x: 0.2775 + (CGFloat(slot - 1) * 0.0555), y: 0.8701)
    }

    func creativeResult(column: Int) -> MinecraftCoordinate {
        precondition((1...4).contains(column), "Only calibrated first-row Creative result columns may be used.")
        return MinecraftCoordinate(x: 0.143 + (CGFloat(column - 1) * 0.055), y: 0.25)
    }

    func craftingSlot(_ slot: MinecraftCraftingSlot) -> MinecraftCoordinate {
        let topLeftX = CGFloat(0.654)
        let topLeftY = CGFloat(0.160)
        let columnStep = CGFloat(0.055)
        let rowStep = CGFloat(0.120)
        let index: (row: Int, column: Int)
        switch slot {
        case .topLeft: index = (0, 0)
        case .topCenter: index = (0, 1)
        case .topRight: index = (0, 2)
        case .middleLeft: index = (1, 0)
        case .middleCenter: index = (1, 1)
        case .middleRight: index = (1, 2)
        case .bottomLeft: index = (2, 0)
        case .bottomCenter: index = (2, 1)
        case .bottomRight: index = (2, 2)
        }
        return MinecraftCoordinate(
            x: topLeftX + (CGFloat(index.column) * columnStep),
            y: topLeftY + (CGFloat(index.row) * rowStep)
        )
    }
}
