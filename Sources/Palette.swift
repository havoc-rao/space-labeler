import Foundation

/// Shared label color palette: 7 light hues with their darker counterparts.
/// The two rows of the picker align column-by-column — light red sits on
/// top of dark red, etc. — so the same hue in two intensities can be used
/// to mark different window states. Both the popover's color picker and
/// `SpaceStore.autoAssign` use this single source. 14 colors + the expand
/// chevron occupy the 8-column grid's final cell, leaving one cell empty.
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

    /// Dark row — same hues, deeper tone; columns 1–6 align with the
    /// light row above (the 7th dark column has no light counterpart).
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