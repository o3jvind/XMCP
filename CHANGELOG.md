# Changelog

All notable changes to XMCP will be documented here.

## [1.6.3] - 2026-06-22

### Fixed
- **CPU spin at idle**: `StdIn.ReadLine` does not block in Xojo's `ConsoleApplication` — it busy-spins when no data is available, causing ~100% CPU usage at idle. Replaced the `While True` / `ReadLine` loop with a `DoEvents(10)`-based loop that accumulates data from `StdIn.ReadAll` into a buffer and processes complete newline-terminated lines as they arrive. Idle CPU usage drops from ~100% to ~1%.

## [1.6.2] - 2026-06-22

### Changed
- **`XOJO_IPCPATH` environment variable support**: XMCP now reads the `XOJO_IPCPATH` environment variable when locating the IDE's IPC socket, consistent with the Xojo IDE Scripting API documentation. If the variable contains a full path it is used directly; if it contains only a filename, `/tmp/` is prepended. Falls back to the standard `/tmp/XojoIDE` and `/private/tmp/XojoIDE` locations when the variable is not set.

## [1.6.1] - 2026-06-16

### Changed
- **Clearer editing guidance in `usage-guide.md`**: "How to edit code" section now explicitly names direct disk editing as the primary path and warns against routing edits through `run_ide_script` + `DoShellCommand` + Python/shell scripts — a fragile workaround that's unnecessary when the MCP client has its own file-editing tools. Also clarifies why `set_code` is not suitable for general editing (no method-level targeting, no `.xojo_window` support).

## [1.6.0] - 2026-06-15

### Added
- **`save_project`**: saves the current project to disk via `DoCommand("SaveFile")` — no parameters required. Use after `set_code` or other IDE edits to persist changes before building or running.
- **`analyze_project`**: runs `CheckProjectErrors` (or `CheckItemErrors` with `scope="item"`) without building. Returns a formatted list of errors and warnings using the same structure as `build_project`. Warnings return as success (they don't block builds); errors return as failure.
- **`debug_control`**: controls an active debug session. Supports `step_over`, `step_into`, `step_out`, `resume`, and `pause` via the `action` parameter.

## [1.5.0] - 2026-06-07

### Added
- **`MainMenuBar.xojo_menu` example**: reference template for the `.xojo_menu` file format — menu bar with File/Edit/Window/Help menus, separators, keyboard shortcuts, and `DesktopQuitMenuItem`
- **`DetailWindow.xojo_window` example**: reference template for non-singleton windows (`ImplicitInstance = False`) — demonstrates the `LoadItem()` pre-population pattern, `LayoutControls()`, Default/Cancel button flags, and `Show` vs `ShowModal`
- **Expanded `MyClass.xojo_code` example**: now includes a custom event definition with `RaiseEvent`, a Shared factory method, a Protected method, and a Note block that documents flag values and block ordering
- **Expanded `Module1.xojo_code` example**: now includes a private property and a Note block explaining the differences between module and class files
- **"Xojo file structure rules" section in `usage-guide.md`**: documents the correct block ordering for class, module, and window files; access modifier flag table (`&h0` Public, `&h1` Protected, `&h21` Private); Shared methods; custom event definitions; non-singleton window pattern; Note block format; and MenuHandler syntax

## [1.4.2] - 2026-06-06

### Added
- **`examples/` exposed as MCP resources**: the five reference templates (`App.xojo_code`, `Module1.xojo_code`, `MyClass.xojo_code`, `MyButton.xojo_code`, `Window1.xojo_window`) are now listed via `resources/list` and readable via `resources/read` using `file://examples/<filename>` URIs — AI clients can fetch them directly without needing filesystem access
- **Build copy steps**: `usage-guide.md` and the `examples/` folder are now copied next to the binary at build time, so distributed builds are self-contained

## [1.4.1] - 2026-06-05

### Fixed
- **100% CPU spin on client exit**: `Input` does not raise `IOException` at EOF — it returns an empty string, causing the read loop to busy-spin indefinitely when the spawning client closed stdin. Switched to `StdIn.ReadLine` + `StdIn.EndOfFile` check, which correctly detects EOF and calls `Quit` to terminate the process.

## [1.4.0] - 2026-06-04

### Added
- **Hybrid search for `search_docs`**: semantic search upgraded from vector-only to hybrid (70% cosine similarity + 30% FTS5 BM25). Catches exact API names that pure vector search may miss while retaining semantic relevance for conceptual queries. Falls back gracefully to vector-only on older databases without FTS5.
- **Neighbour chunk expansion**: chunks scoring ≥ 0.72 cosine similarity automatically pull in their adjacent chunks (`prev_id`/`next_id`), preserving context at document split boundaries.
- **Logical result ordering**: results are grouped by source document (highest-scoring source first) and sorted by `chunk_index` within each group, so returned text reads in document order.
- **In-memory query cache**: repeated identical queries are served from a Dictionary cache (max 50 entries) without hitting the database, reducing latency for follow-up questions.
- **Persistent database connection**: `SemanticSearch` now holds a single `SQLiteDatabase` open for the lifetime of the process with WAL mode, 256 MB mmap, and 64 MB page cache — eliminates per-query open/close overhead.

## [1.3.1] - 2026-05-06

### Added
- `examples/` folder next to `usage-guide.md` with reference implementations of common Xojo file structures: `App.xojo_code`, `Module1.xojo_code`, `MyClass.xojo_code`, `MyButton.xojo_code`, `Window1.xojo_window` — gives the AI concrete templates to copy from when creating or editing project files

## [1.3.0] - 2026-05-06

### Changed
- `usage-guide.md`: direct file editing is now the primary approach for all code changes — not a fallback. `get_code`/`set_code` with dot-separated paths are unreliable and the guide no longer recommends them for writing code
- `usage-guide.md`: `get_code`/`set_code` without a location parameter work reliably when the user has already selected code in the IDE — after `set_code`, the AI now reminds the user to save (Cmd+S)
- `usage-guide.md`: `build_project` always reports "Build succeeded" regardless of outcome — AI now always asks the user to confirm the build succeeded
- `usage-guide.md`: `get_debug_log` is only useful in built apps — the Xojo debugger intercepts all exceptions in debug mode so they never reach the log. The log may contain data from a previous crash; always call `get_debug_log` with `clear: true` after reading
- `usage-guide.md`: `list_doc_topics` should not be used for lookups — use `search_docs` instead to avoid wasting tokens on the full 143,000-character index
- `usage-guide.md`: runtime exceptions in debug mode are visible to the user in the IDE debugger but not to XMCP
- `select_project_item`: error message no longer suggests using `get_code`/`set_code` with dot-path as an alternative
- CLAUDE.md/README.md: corrected incorrect claim that `.xojo_project` is XML (it is key/value text format)

## [1.2.0] - 2026-02-24

### Added
- MCP `resources` protocol support: `resources/list` and `resources/read` — clients can now fetch `usage-guide.md` as an MCP resource at session start
- `get_project_info` now returns a `Project Directory:` line with the full path to the project folder, enabling direct file editing workflows
- `usage-guide.md` is now distributed next to the binary and exposed as an MCP resource — AI clients receive it automatically; users can edit it without rebuilding

### Fixed
- Shell injection prevention in `get_system_log`: `process_name` parameter is now validated against a whitelist regex before interpolation into the shell command
- JSON-RPC `id` type preservation: integer ids are now correctly echoed back as integers (not coerced to strings), fixing protocol compliance
- `ToolParameter.ToJSONItem` now emits correct JSON types for Boolean and Integer defaults (not always String)
- `MCPKit.Error()` now emits JSON `null` for missing ids instead of an empty string
- `get_selected_text` and `set_selected_text` now return `Failure` instead of `Success` when the IDE returns an `ERROR:` string
- RequestID lookup fixed: integer ids no longer cause the server to exit with "Missing id" on subsequent requests

### Changed
- `get_system_log` now works for both debug builds (`AppName.debug`) and built apps (`AppName`) — not just debug builds as previously documented
- Actionable error messages in `select_project_item`, `get_code`, and `set_code`: errors now guide the AI to the correct alternative strategy (direct file editing, `revert_project`, etc.)
- `usage-guide.md` expanded with tested guidance: window event handler file format, `list_project_items` event limitation, debug vs. built app logging behavior

## [1.1.0] - 2026-02-23

### Added
- `get_debug_log` tool: reads crash/exception info written by `App.UnhandledException` handlers to `/tmp/xmcp_debug.log`
- `get_system_log` tool: reads `System.DebugLog` output from the macOS unified log for a named debug app process (e.g. `MyApp.debug`)

### Fixed
- `build_project` now correctly passes build type and reveal flag to `DoCommand "BuildApp"` as a single string argument (e.g. `"BuildApp 24 True"`) — comma-separated arguments caused a script compiler error
- XMCP server processes now terminate gracefully when the MCP client closes stdin, preventing zombie processes from accumulating
- `run_project` and `build_project` now correctly capture and report compile errors from the Xojo IDE instead of always returning success
- Error output is formatted as a readable list with error type, message, location, and position

### Changed
- `search_docs` description clarified: it searches guides and tutorials, not the API reference — use `lookup_class` for class/method/property lookups

## [1.0.0] - 2026-01-01

### Added
- Initial release with 20 tools for controlling the Xojo IDE via MCP
