import Foundation

/// Shared label color palette: 6 light hues with their darker counterparts.
/// The two rows of the picker align column-by-column — light red sits on
/// top of dark red, etc. — so the same hue in two intensities can be used
/// to mark different window states. Both the popover's color picker and
/// `SpaceStore.autoAssign` use this single source. The picker layout is
/// fixed: the first row is always the 6 light swatches + the expand
/// chevron (7 cells); expanding adds the 7 dark swatches as a second row,
/// with the 7th dark column sharing the chevron's column.
enum SpacePalette {
    /// Light row — the default collapsed view. 6 entries so the 7th
    /// grid cell is free for the expand chevron.
    static let lightColors = [
        "#F87171",  // 红
        "#4ADE80",  // 绿
        "#60A5FA",  // 蓝
        "#FBBF24",  // 黄
        "#A78BFA",  // 紫
        "#2DD4BF",  // 青
    ]

    /// Dark row — the expanded view's second row; same hues, deeper tone.
    /// Columns 1–6 align with the light row above (the 7th dark column has
    /// no light counterpart, sharing the chevron's column instead).
    static let darkColors = [
        "#B91C1C",  // 深红
        "#15803D",  // 深绿
        "#1D4ED8",  // 深蓝
        "#A16207",  // 深黄
        "#6D28D9",  // 深紫
        "#0F766E",  // 深青
        "#BE185D",  // 深粉
    ]

    static let colors = lightColors + darkColors
}