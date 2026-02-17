//! Tests for TUI components
//! Comprehensive tests for all TUI components functionality

const std = @import("std");
const testing = std.testing;
const tui = @import("tui");
const components = tui.components;
const renderer = tui.renderer;
const events = tui.events;

test "List component basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var list = components.List.init(allocator, 0, 0, 20, 5);
    defer list.deinit();

    // Test adding items
    try list.addItem("Item 1");
    try list.addItem("Item 2");
    try list.addItem("Item 3");

    try testing.expect(list.getItemCount() == 3);
    try testing.expect(list.getSelectedIndex().? == 0);

    // Test navigation
    list.moveDown();
    try testing.expect(list.getSelectedIndex().? == 1);

    list.moveUp();
    try testing.expect(list.getSelectedIndex().? == 0);

    // Test wrapping
    list.moveUp(); // Should wrap to last item
    try testing.expect(list.getSelectedIndex().? == 2);

    // Test selection
    const selected = list.getSelectedItem().?;
    try testing.expectEqualStrings("Item 3", selected.text);

    // Test removal
    list.removeItem(1);
    try testing.expect(list.getItemCount() == 2);
}

test "InputField component validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var input = components.InputField.init(allocator, 0, 0, 10);
    defer input.deinit();

    // Test basic text input
    try input.setText("hello");
    try testing.expectEqualStrings("hello", input.getText());

    // Test validation
    input.setValidator(components.validateNotEmpty);

    input.clear();
    try testing.expect(!input.isValid()); // Empty should be invalid

    try input.setText("test");
    try testing.expect(input.isValid()); // Non-empty should be valid

    // Test hex color validation
    input.setValidator(components.validateHexColor);

    try input.setText("#FF0000");
    try testing.expect(input.isValid());

    try input.setText("invalid");
    try testing.expect(!input.isValid());

    // Test max length
    input.setMaxLength(5);
    try input.setText("toolong");
    try testing.expectEqualStrings("toolo", input.getText()); // Should be truncated
}

test "ProgressBar component" {
    var progress = components.ProgressBar.init(0, 0, 20);

    // Test initial state
    try testing.expect(progress.getProgress() == 0.0);

    // Test setting progress
    progress.setProgress(0.5);
    try testing.expect(progress.getProgress() == 0.5);

    // Test clamping
    progress.setProgress(1.5);
    try testing.expect(progress.getProgress() == 1.0);

    progress.setProgress(-0.5);
    try testing.expect(progress.getProgress() == 0.0);

    // Test style changes
    progress.setStyle(components.ProgressStyle.bars);
    progress.setShowPercentage(false);
    progress.setLabel("Test Progress");
}

test "AnimatedProgressBar component" {
    var animated = components.AnimatedProgressBar.init(0, 0, 20);

    // Test initial state
    try testing.expect(animated.getProgress() == 0.0);
    try testing.expect(!animated.isAnimating());

    // Test target setting
    animated.setTargetProgress(0.8);
    try testing.expect(animated.isAnimating());

    // Test animation update
    animated.update(0.1); // 0.1 seconds
    try testing.expect(animated.getProgress() > 0.0);
    try testing.expect(animated.getProgress() < 0.8);

    // Test animation completion
    animated.update(1.0); // 1 second should complete
    try testing.expect(animated.getProgress() == 0.8);
    try testing.expect(!animated.isAnimating());
}

test "ColorPicker component" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var picker = components.ColorPicker.init(allocator, 0, 0, 20, 8);
    defer picker.deinit();

    // Test initial color
    const initial_color = picker.getColor();
    try testing.expect(initial_color.r == 255);
    try testing.expect(initial_color.g == 255);
    try testing.expect(initial_color.b == 255);

    // Test setting color
    const red = renderer.Color{ .r = 255, .g = 0, .b = 0 };
    picker.setColor(red);
    const current_color = picker.getColor();
    try testing.expect(current_color.r == 255);
    try testing.expect(current_color.g == 0);
    try testing.expect(current_color.b == 0);

    // Test mode switching
    picker.setMode(components.ColorMode.rgb);
    picker.setMode(components.ColorMode.hsv);
    picker.setMode(components.ColorMode.hex);
}

test "Dropdown component" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dropdown = components.Dropdown.init(allocator, 0, 0, 15);
    defer dropdown.deinit();

    // Test adding options
    try dropdown.addOption("Option 1", "opt1");
    try dropdown.addOption("Option 2", "opt2");
    try dropdown.addOption("Option 3", "opt3");

    try testing.expect(dropdown.getOptionCount() == 3);

    // Test selection
    try testing.expectEqualStrings("Option 1", dropdown.getSelectedText().?);
    try testing.expectEqualStrings("opt1", dropdown.getSelectedValue().?);

    // Test selection by value
    try testing.expect(dropdown.setSelectedByValue("opt2"));
    try testing.expectEqualStrings("Option 2", dropdown.getSelectedText().?);

    // Test invalid selection
    try testing.expect(!dropdown.setSelectedByValue("invalid"));

    // Test open/close
    try testing.expect(!dropdown.isOpen());
    dropdown.open();
    try testing.expect(dropdown.isOpen());
    dropdown.close();
    try testing.expect(!dropdown.isOpen());

    // Test toggle
    dropdown.toggle();
    try testing.expect(dropdown.isOpen());
    dropdown.toggle();
    try testing.expect(!dropdown.isOpen());
}

test "Component event handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test List event handling
    var list = components.List.init(allocator, 0, 0, 20, 5);
    defer list.deinit();

    try list.addItem("Item 1");
    try list.addItem("Item 2");

    list.setFocus(true);

    // Test up/down navigation
    const down_event = events.Event{ .key = events.KeyEvent{ .key = events.Key.down } };
    try testing.expect(try list.handleEvent(down_event));
    try testing.expect(list.getSelectedIndex().? == 1);

    const up_event = events.Event{ .key = events.KeyEvent{ .key = events.Key.up } };
    try testing.expect(try list.handleEvent(up_event));
    try testing.expect(list.getSelectedIndex().? == 0);

    // Test InputField event handling
    var input = components.InputField.init(allocator, 0, 0, 10);
    defer input.deinit();

    input.setFocus(true);

    // Test character input
    const char_event = events.Event{ .key = events.KeyEvent{ .key = events.Key.char, .char = 'a' } };
    try testing.expect(try input.handleEvent(char_event));
    try testing.expectEqualStrings("a", input.getText());

    // Test backspace
    const backspace_event = events.Event{ .key = events.KeyEvent{ .key = events.Key.backspace } };
    try testing.expect(try input.handleEvent(backspace_event));
    try testing.expectEqualStrings("", input.getText());

    // Test Dropdown event handling
    var dropdown = components.Dropdown.init(allocator, 0, 0, 15);
    defer dropdown.deinit();

    try dropdown.addOption("Option 1", "opt1");
    try dropdown.addOption("Option 2", "opt2");

    dropdown.setFocus(true);

    // Test opening dropdown
    const enter_event = events.Event{ .key = events.KeyEvent{ .key = events.Key.enter } };
    try testing.expect(try dropdown.handleEvent(enter_event));
    try testing.expect(dropdown.isOpen());

    // Test navigation in open dropdown
    try testing.expect(try dropdown.handleEvent(down_event));
    try testing.expectEqualStrings("Option 2", dropdown.getSelectedText().?);

    // Test closing dropdown
    try testing.expect(try dropdown.handleEvent(enter_event));
    try testing.expect(!dropdown.isOpen());
}

test "Component focus and visibility" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var list = components.List.init(allocator, 0, 0, 20, 5);
    defer list.deinit();

    try list.addItem("Item 1");

    // Test focus
    try testing.expect(!list.focused);
    list.setFocus(true);
    try testing.expect(list.focused);

    // Test visibility
    try testing.expect(list.visible);
    list.setVisible(false);
    try testing.expect(!list.visible);

    // Test that invisible components don't handle events
    const event = events.Event{ .key = events.KeyEvent{ .key = events.Key.down } };
    try testing.expect(!try list.handleEvent(event));

    // Test that unfocused components don't handle events
    list.setVisible(true);
    list.setFocus(false);
    try testing.expect(!try list.handleEvent(event));
}

test "Input validation functions" {
    // Test validateNotEmpty
    const empty_result = components.validateNotEmpty("");
    try testing.expect(switch (empty_result) {
        .invalid => true,
        .valid => false,
    });

    const non_empty_result = components.validateNotEmpty("test");
    try testing.expect(switch (non_empty_result) {
        .valid => true,
        .invalid => false,
    });

    // Test validateNumber
    const valid_number = components.validateNumber("123");
    try testing.expect(switch (valid_number) {
        .valid => true,
        .invalid => false,
    });

    const invalid_number = components.validateNumber("abc");
    try testing.expect(switch (invalid_number) {
        .invalid => true,
        .valid => false,
    });

    // Test validateHexColor
    const valid_hex = components.validateHexColor("#FF0000");
    try testing.expect(switch (valid_hex) {
        .valid => true,
        .invalid => false,
    });

    const invalid_hex = components.validateHexColor("FF0000");
    try testing.expect(switch (invalid_hex) {
        .invalid => true,
        .valid => false,
    });
}
