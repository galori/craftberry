import CoreGraphics

struct MinecraftCalibratedLayout {
    let creativeSearchField = MinecraftCoordinate(x: 0.29, y: 0.155)
    let creativeSearchClearButton = MinecraftCoordinate(x: 0.463, y: 0.155)
    let craftingOutput = MinecraftCoordinate(x: 0.709, y: 0.756)
    let stagingHotbarSlot = MinecraftCoordinate(x: 0.611, y: 0.91)
    let closeCraftingTable = MinecraftCoordinate(x: 0.947, y: 0.065)
    let reopenCraftingTable = MinecraftCoordinate(x: 0.5075, y: 0.265)

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
