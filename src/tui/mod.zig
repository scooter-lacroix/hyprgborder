//! TUI module exports
//! This module provides the Terminal User Interface functionality

pub const menu = @import("menu.zig");
pub const preview = @import("preview.zig");
pub const renderer = @import("renderer.zig");
pub const events = @import("events.zig");

pub const app = @import("app.zig");
pub const components = @import("components/mod.zig");
pub const screens = @import("screens/mod.zig");

// Re-export commonly used types
pub const Renderer = renderer.Renderer;
pub const EventHandler = events.EventHandler;
pub const SimpleEventHandler = events.SimpleEventHandler;
pub const TUIApp = app.TUIApp;
pub const Event = events.Event;
pub const KeyEvent = events.KeyEvent;
pub const Key = events.Key;
