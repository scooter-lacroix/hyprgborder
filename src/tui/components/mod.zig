//! TUI Components module
//! Provides reusable UI components for the Terminal User Interface

pub const Panel = @import("panel.zig").Panel;
pub const Text = @import("text.zig").Text;
pub const List = @import("list.zig").List;
pub const InputField = @import("input_field.zig").InputField;
pub const ProgressBar = @import("progress.zig").ProgressBar;
pub const AnimatedProgressBar = @import("progress.zig").AnimatedProgressBar;
pub const ColorPicker = @import("color_picker.zig").ColorPicker;
pub const Dropdown = @import("dropdown.zig").Dropdown;

// Re-export validation functions
pub const validateNotEmpty = @import("input_field.zig").validateNotEmpty;
pub const validateNumber = @import("input_field.zig").validateNumber;
pub const validateFloat = @import("input_field.zig").validateFloat;
pub const validateFpsInput = @import("input_field.zig").validateFpsInput;
pub const validateHexColor = @import("input_field.zig").validateHexColor;

// Re-export enums and types
pub const ProgressStyle = @import("progress.zig").ProgressStyle;
pub const ColorMode = @import("color_picker.zig").ColorMode;

// Re-export common types
pub const Component = union(enum) {
    panel: Panel,
    text: Text,
    list: List,
    input_field: InputField,
    progress_bar: ProgressBar,
    animated_progress_bar: AnimatedProgressBar,
    color_picker: ColorPicker,
    dropdown: Dropdown,
};
