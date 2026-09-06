# Changelog

All notable changes to XMCP will be documented here.

## [1.9.0] - 2026-09-06

### Added
- **`scaffold_code_block`**: generates a correctly formatted `#tag` block (Method, Property, Constant, Event definition, Shared method, control event handler, or window event handler) for the caller to insert directly into a `.xojo_code`/`.xojo_window` file, instead of hand-writing `#tag` syntax from memory.
- **`lint_project_file`**: validates a `.xojo_code`/`.xojo_window` file on disk for the four known failure modes — wrong `#tag` block ordering, `Flags`/keyword mismatches, unclosed or mismatched `#tag`/`#tag End` pairs, and unescaped characters in Constant `Default` values. Reports errors and warnings; never modifies the file.
- Both tools read their format rules from a machine-readable JSON block embedded in `usage-guide.md` (`FormatRules.xojo_code`), so a rule fix or newly discovered edge case takes effect on the next tool call — no rebuild required.
- `src/examples/` is now itself a real, buildable Xojo Desktop project (`Examples.xojo_project`), rebuilt entirely from IDE-generated content. Previously the reference templates were static, hand-authored text that was never compiled or validated by the Xojo IDE.

### Fixed
- Two silent, previously undetected bugs in the `examples/` reference templates, found only because they are now IDE-validated: `App.xojo_code`'s `Inherits Application` was deprecated API 1 (fixed to `Inherits DesktopApplication`); a hand-written Constant `Default` value with an unescaped opening quote compiled without error but silently dropped the value's first character at runtime.
- `Window (deprecated class)`'s `Close` event name corrected to the API 2 `Closing` in the `DetailWindow` example, which had carried the deprecated name.

### Notes
Building and testing the two new tools surfaced several previously undocumented Xojo behaviors, now recorded in `CLAUDE.md`:
- The bare `Tab` identifier is invalid in a Console Application target and produces a cascade of confusing, unrelated-looking compile errors.
- `String.BeginsWith` and `String.IndexOf` are case-insensitive by default in this Xojo version — this broke `#tag` scanning against Xojo's own `#Tag Instance, Platform = ...` per-platform Constant override syntax until fixed with explicit `ComparisonOptions.CaseSensitive`.
- `.xojo_code` Constant `Default` values use the same escape table as `.xojo_window` (`\x2C`, `\x3D`, `\'`, `\xHH`) for comma/equals/apostrophe/non-ASCII — not the simpler `""`-doubling previously assumed.
- A custom event definition inside a class body is serialized by the IDE as `#tag Hook`, not `#tag Event` — `#tag Event` is reserved for overriding an already-inherited event.

## [1.8.1] - 2026-08-14

### Fixed
- **Retrieval scoring kept in sync with XDOX's MBS docset support**: XDOX now
  indexes the MBS Xojo Plugins documentation under its own `docs_version`
  sentinel (`"mbs"`) instead of the version-independent `''`, so `SemanticSearch`'s
  version filters (`KeywordSearch`, hybrid vector search) are updated to include
  `docs_version = "mbs"` alongside the active Xojo version — without this, MBS
  chunks would have silently dropped out of `search_docs`/`lookup_class` results
  once XDOX's own filter changed. Also ported XDOX's class-name-exact-match score
  boost (`ExtractClassName`): cosine similarity alone doesn't reliably separate
  similarly-named MBS classes (e.g. `DesktopWKWebViewControlMBS` vs
  `DesktopWebView2ControlMBS`) within the handful of results actually returned,
  so a query naming a class exactly now gets a flat boost toward that class's
  chunks. Both changes mirror XDOX's `Retrieval.xojo_code` — the scoring recipe
  is deliberately duplicated on both sides.

## [1.8.0] - 2026-07-09

### Added
- **Multiple Xojo versions**: XDOX (schema v3) can now index several Xojo doc versions side by side in one `xdox.db`, each chunk tagged with its `docs_version`. `search_docs` filters results to the version XDOX currently has active (`metadata.active_docs_version`, read fresh on every search so a live version switch in XDOX takes effect immediately) plus version-independent curated chunks (`docs_version = ''`). Result headers show the active version. This mirrors XDOX's `Retrieval` — the same filter is deliberately duplicated on both sides.

### Changed
- **Note relevance labelling**: notes now carry a `scope` (`all` = global/version-independent, or `version`). Only version-scoped notes can show the `[possibly outdated — written for …]` caveat; global notes never do. `search_notes` still searches **all** notes regardless of scope — nothing is filtered out, so Claude never silently misses a note.

### Compatibility
- Legacy databases (`xojo_rag.db`, or XDOX schema < 3 without the `docs_version`/`scope` columns) are detected at attach and the new filters are skipped — search behaves exactly as before against them.

## [1.7.1] - 2026-07-06

### Added
- **Hybrid `search_notes`**: notes are now scored semantically (0.7·cosine + 0.3·BM25, relevance floor 0.45 — same recipe as XDOX's chat) whenever the embedding server answers, so natural-language queries find notes that share no keywords with the question. Falls back to the keyword tier unchanged.

### Fixed
- **Startup-order dependency**: the RAG database and the embedding server were probed exactly once, at process start. XMCP typically starts with the editor — *before* XDOX — and would then sit in the lowest search tier until restarted. Both are now re-checked lazily at search time (server probes are rate-limited to one per 30 s while down), so search upgrades itself the moment XDOX comes up. The XDOX database path is used even when the file doesn't exist yet, covering first launch and post-schema-bump reindexes.
- `search_docs` drops back to the keyword tier immediately when the embedding server disappears mid-session (previously each search paid a failed HTTP round-trip).

## [1.7.0] - 2026-07-06

### Added
- **`search_notes`**: searches the user's personal Xojo notes, written and curated in the [XDOX](https://github.com/o3jvind/XDOX) app. Notes flagged `[possibly outdated — written for Xojo <version>]` predate the currently indexed docs version. Responds gracefully against legacy databases without notes tables.
- **`--db-path` option**: explicit RAG-database override. Default discovery order is now `--db-path` → `~/Library/Application Support/dk.o3jvind.xdox/xdox.db` (built and maintained by the XDOX app, which replaces XMCP-RAG-Indexer) → legacy `xojo_rag.db` next to the documentation.
- **Keyword (BM25) search tier**: `search_docs` now degrades semantic → keyword → plain text scan. The keyword tier runs FTS5/BM25 against the RAG database and needs no embedding server, replacing the `llms-full.txt` substring scan as the primary fallback.
- **Metadata validation**: `embedding_dim` ≠ 768 disables the semantic tier (keyword still works); the indexed `docs_version` is included in `search_docs`/`search_notes` result headers.

### Changed
- `SemanticSearch` keeps the database connection open when the embedding server is down (previously it discarded both), and the startup server probe fails fast (2 s + connection-error handler) instead of hanging up to 10 s.

### Notes
- The embedding server on port 8089 is managed automatically by the XDOX app while it runs. Semantic search is available whenever XDOX (or a manually started server) is up; keyword search works at all times.
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
