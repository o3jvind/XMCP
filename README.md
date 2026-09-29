# XMCP

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that gives AI assistants direct control over the [Xojo IDE](https://www.xojo.com). Built in Xojo using [MCPKit](https://github.com/gkjpettet/MCPKit) by Garry Pettet.

XMCP connects to the Xojo IDE via its IPC socket, all through the standard MCP protocol over stdin/stdout.

## What XMCP can do

34 tools in total on macOS and 33 on Windows (31 and 30 always on, plus 3 opt-in; `get_system_log` reads the macOS system log and is not registered on Windows) across seven categories — see [Tools](#tools) below for the full reference on each one:

- **IDE Tools** (19) — navigate, read/write code, build, run, save, analyze, control debug sessions, create items, inspect/modify item descriptions and constants, revert from disk, and run arbitrary IDE scripts
- **Documentation Tools** (4) — search Xojo's bundled documentation and the user's personal notes, look up class references, list topics
- **Docset Tools** (3) — search any third-party Dash/Zeal `.docset` bundle, independent of the Xojo-specific tools (works for any language with a docset)
- **Debug Tools** (2) — read crash logs and system output
- **Cost Awareness** (1) — estimate the likely token cost of a request before running it, with cheaper alternatives
- **Disk-File Generation and Validation** (2) — generate or validate `.xojo_code`/`.xojo_window` `#tag` syntax directly on disk, no IDE required
- **File Tools** (3, opt-in) — `write_file`/`read_file`/`hash_file`, for MCP clients with no file tools of their own (e.g. Claude Desktop)

XMCP is built Xojo-first: the IDE tools, the bundled documentation search, and the `examples/` reference templates all exist because the author is a Xojo developer. But nothing in its architecture is Xojo-*only* — the documentation layer (see [Adapting XMCP to your stack](#adapting-xmcp-to-your-stack)) works for any language with a Dash/Zeal docset, and a project working in multiple languages can register several at once.

XMCP also ships a `usage-guide.md` file next to the binary, exposed as an MCP resource. Compatible clients (e.g. Claude Code) fetch it automatically at session start, giving the AI immediate awareness of XMCP's capabilities, known IDE scripting limitations, and fallback strategies — without any extra configuration. You can edit the file to add project-specific notes without rebuilding.

## Requirements

- **Xojo IDE** available for IDE tools (its IPC socket path is discovered automatically; see [IDE Communication](#ide-communication))
- **macOS or Windows** - both are supported. On Windows the socket resolves under `%LOCALAPPDATA%\Temp` and `get_system_log` is unavailable (see [Known Limitations](#known-limitations)); Linux is untested
- **Xojo documentation** (optional) - install via **Xojo IDE → Preferences → General → Install Local Documentation**, then auto-detected by XMCP

## Installation

1. Open `src/XMCP.xojo_project` in the Xojo IDE
2. Build the project (Build > Build)
3. Note the path to the built `XMCP` binary

### Configure your MCP client

**Claude Code** (`~/.claude.json` or project `.mcp.json`):

```json
{
  "mcpServers": {
    "xmcp": {
      "command": "/path/to/XMCP"
    }
  }
}
```

**Claude Desktop** (`claude_desktop_config.json`):

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

Create the file if it doesn't exist yet. Claude Desktop has no file tools of its own, so it's the client most people want `--enable-file-tools` for — a complete config combining that with a custom documentation path looks like this (every flag lives in the same `args` array; see [Usage](#usage) below for the full list):

```json
{
  "mcpServers": {
    "xmcp": {
      "command": "/path/to/XMCP",
      "args": [
        "--docs-path", "/path/to/Documentation",
        "--enable-file-tools",
        "--file-root", "/tmp,/path/to/your/projects"
      ]
    }
  }
}
```

Fully quit and reopen Claude Desktop after saving — it only reads this file at launch, so a reload isn't enough.

**OpenAI Codex CLI** (`~/.codex/config.toml`):

```toml
[mcp_servers.xmcp]
command = "/path/to/XMCP"
```

Any other MCP-capable client works the same way — XMCP speaks standard MCP over stdin/stdout, so point the client at the binary as its server command.

To specify a custom documentation path:

```json
{
  "mcpServers": {
    "xmcp": {
      "command": "/path/to/XMCP",
      "args": ["--docs-path", "/path/to/Documentation"]
    }
  }
}
```

To register one or more third-party `.docset` bundles (repeat the flag per bundle — see [Adapting XMCP to your stack](#adapting-xmcp-to-your-stack)):

```json
{
  "mcpServers": {
    "xmcp": {
      "command": "/path/to/XMCP",
      "args": [
        "--docset-path", "/path/to/PHP.docset",
        "--docset-path", "/path/to/JavaScript.docset"
      ]
    }
  }
}
```

To enable the opt-in file tools for a client with no file tools of its own (e.g. Claude Desktop):

```json
{
  "mcpServers": {
    "xmcp": {
      "command": "/path/to/XMCP",
      "args": ["--enable-file-tools", "--file-root", "/tmp,/Users/you/GitHub"]
    }
  }
}
```

## Usage

```
XMCP [options]
```

| Option | Description |
|--------|-------------|
| `-h`, `--help` | Show help and list all available tools |
| `-v`, `--verbose` | Enable verbose debug logging to stderr |
| `-d`, `--docs-path PATH` | Path to Xojo documentation directory (auto-detected if omitted) |
| `--docset-path PATH` | Path to a Dash/Zeal-style `.docset` bundle. Repeatable — pass once per bundle. |
| `--enable-file-tools` | Enable the `write_file`/`read_file`/`hash_file` tools (disabled by default) |
| `--file-root PATHS` | Comma-separated absolute paths the file tools may access (default: `/tmp`) |

The server communicates via JSON-RPC over stdin/stdout following the MCP protocol. It is not meant to be run interactively - it is launched by an MCP client (like Claude Code, Codex CLI, or Claude Desktop).

You can start XMCP before the Xojo IDE. IDE-dependent tools will return an error until the IDE socket is available.
XMCP retries both standard socket paths on each IDE request, so tools begin working automatically once the IDE starts.

## Tools

Full reference for every tool, organized into the same seven categories as [above](#what-xmcp-can-do).

### IDE Tools

These tools communicate with the Xojo IDE through its IPC socket to navigate, read, write, build, and manage projects.

#### `list_project_items`

Lists child items at a given location in the Xojo IDE Navigator. Returns a tab-delimited list of item names.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `location` | String | No | Dot-separated project path (e.g. `App` or `Module1.Method1`). Leave empty for top-level items. |

#### `get_current_location`

Returns the currently selected location in the Xojo IDE Navigator and its type (e.g. Class, Method, Window).

*No parameters.*

#### `select_project_item`

Navigates to a specific item in the Xojo IDE Navigator using a dot-separated path.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `item_path` | String | Yes | Dot-separated path to the project item (e.g. `App`, `Module1.MyMethod`). |

#### `get_code`

Reads the source code at the current location in the IDE editor. The `location` parameter is unreliable — omit it and use the IDE's current selection instead.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `location` | String | No | Dot-separated path to navigate to before reading. If empty, reads from current location. |

#### `set_code`

Writes source code to the current location in the IDE editor. Replaces the entire code content at that location. The `location` parameter is unreliable — omit it and use the IDE's current selection instead. Does not save to disk; the user must save manually (Cmd+S).

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `code` | String | Yes | The source code to write. |
| `location` | String | No | Dot-separated path to navigate to before writing. If empty, writes to current location. |

#### `get_selected_text`

Returns the currently selected text in the code editor, along with selection position and length.

*No parameters.*

#### `set_selected_text`

Replaces the currently selected text in the code editor with new text.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `text` | String | Yes | The replacement text to insert. |
| `selection_start` | Integer | No | Character offset to set the selection start before replacing. Default: -1 (use current). |
| `selection_length` | Integer | No | Number of characters to select before replacing. Default: 0. |

#### `build_project`

Builds the current Xojo project using the IDE's configured Build Settings (the target platforms selected in the IDE). Returns "Build succeeded." on success, or a formatted list of build errors on failure.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `timeout` | Integer | No | How long to wait for the build, in milliseconds. Default: 1800000 (30 minutes); zero or negative means the default. Giving up does not stop the IDE: if it takes longer, the request is left waiting (*parked*) until the IDE answers, and you must not quit or restart Claude Code in the meantime - see [When the IDE does not answer](#when-the-ide-does-not-answer). If you expect a long build, pass a longer `timeout` rather than letting it run over. |

#### `run_project`

Runs the current Xojo project in debug mode.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `timeout` | Integer | No | How long to wait for the project to build and launch, in milliseconds. Default: 1800000 (30 minutes); zero or negative means the default. Giving up does not stop the IDE: if it takes longer, the request is left waiting (*parked*) until the IDE answers, and you must not quit or restart Claude Code in the meantime - see [When the IDE does not answer](#when-the-ide-does-not-answer). If you expect a long build before it launches, pass a longer `timeout` rather than letting it run over. |

#### `stop_project`

Stops the currently running debug session.

*No parameters.*

#### `create_project_item`

Creates a new project item in the Xojo IDE.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `item_type` | String | Yes | One of: `NewClass`, `NewModule`, `NewMethod`, `NewProperty`, `NewConstant`, `NewEvent`, `NewNote`, `NewMenuHandler`, `NewComputedProperty`, `NewSharedMethod`, `NewSharedProperty`, `NewEnum`, `NewStructure`, `NewDelegate`, `NewInterface`, `NewWindow`, `NewContainerControl`, `NewFolder`, `AddEventImplementation`. |
| `parent_location` | String | No | Dot-separated path to navigate to before creating the item (e.g. `Module1`). |

#### `run_ide_script`

Executes an arbitrary Xojo IDE script. This is an escape hatch for any IDE scripting command not covered by other tools.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `script` | String | Yes | The IDE script code to execute. Use `Print` to return output values. |
| `timeout` | Integer | No | How long to wait for the script, in milliseconds. Default: 10000 (10 seconds); zero or negative means the default. Giving up does not stop the IDE: if the script runs longer - or opens a dialog - the request is left waiting (*parked*) until the IDE answers, and you must not quit or restart Claude Code in the meantime - see [When the IDE does not answer](#when-the-ide-does-not-answer). |

#### `get_project_info`

Returns information about the currently open project including the project file path, Xojo IDE version, current location, location type, and selected item.

*No parameters.*

#### `revert_project`

Reverts the current Xojo project to the version saved on disk. Use this after modifying project files (e.g. `.xojo_window`, `.xojo_code`) directly to reload them in the IDE.

*No parameters.*

#### `get_item_description`

Gets or sets the description of the currently selected project item (method, property, event, etc.).

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `location` | String | No | Dot-separated path to navigate to before reading/writing (e.g. `App.MyMethod`). If empty, uses current location. |
| `value` | String | No | If provided, sets the description to this value. If omitted, returns the current description. |

#### `constant_value`

Gets or sets the value of a project constant. The constant must already exist in the project.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | String | Yes | The fully-qualified constant name (e.g. `App.kVersion`). A bare name (e.g. `kVersion`) silently fails in the Xojo IDE scripting API — always qualify with the containing module or class. |
| `value` | String | No | If provided, sets the constant to this value. If omitted, returns the current value. |

#### `save_project`

Saves the current Xojo project to disk. Call this after making changes via `set_code` or other IDE tools to persist them before building or running.

*No parameters.*

#### `analyze_project`

Analyzes the current Xojo project for compile errors and warnings without building. Reports unused variables, type mismatches, deprecated API usage, and other issues. Warnings return as success (they don't block building); errors return as failure.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scope` | String | No | `"project"` (default) — analyze entire project; `"item"` — analyze only the currently selected item. |
| `timeout` | Integer | No | How long to wait for the analysis, in milliseconds. Default: 300000 (5 minutes); zero or negative means the default. A large project can take longer than the fixed 60 seconds this used to allow. Giving up does not stop the IDE: if it takes longer, the request is left waiting (*parked*) until the IDE answers, and you must not quit or restart Claude Code in the meantime - see [When the IDE does not answer](#when-the-ide-does-not-answer). If you expect a long analysis, pass a longer `timeout` rather than letting it run over. |

#### `debug_control`

Controls an active Xojo debug session. Requires a running debug session started with `run_project`.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | String | Yes | One of: `"step_over"`, `"step_into"`, `"step_out"`, `"resume"`, `"pause"`. |

### Documentation Tools

These tools provide access to the local Xojo documentation, enabling the AI to look up classes, search for APIs, and browse available topics. Documentation is auto-detected from `~/Library/Application Support/Xojo/Xojo/<version>/Documentation/` or can be specified with `--docs-path`.

#### `search_docs`

Searches the local Xojo documentation guides and tutorials. Returns matching sections with title and content. Use this for conceptual questions about language features, patterns, and best practices. To look up a specific class, method, or property by name, use `lookup_class` instead.

`search_docs` searches a RAG database and degrades gracefully through three tiers — no configuration required:

1. **Semantic (hybrid)** — when the RAG database is found *and* the embedding server responds on `localhost:8089` (the [XDOX](https://github.com/o3jvind/XDOX) app manages one automatically while it runs).
2. **Keyword (BM25)** — when only the database is available: FTS5 full-text search, still high quality.
3. **Plain text scan** of `llms-full.txt` — last resort when no database exists.

**Database discovery order:** `--db-path` (explicit) → `~/Library/Application Support/dk.o3jvind.xdox/xdox.db` (built and kept up to date by the XDOX app — the recommended setup) → `xojo_rag.db` next to the documentation (legacy XMCP-RAG-Indexer output).

**Multiple Xojo versions:** when XDOX has indexed more than one Xojo version, `search_docs` returns results for the version XDOX currently has active (its status-bar version picker), plus version-independent chunks — the active version is read fresh on every search, so switching it in XDOX takes effect immediately with no restart. Result headers name that version. Legacy databases without per-version data are unaffected.

**Hybrid search pipeline:**
1. Embeds the query with the local embedding model
2. Scores all chunks by cosine similarity (vector search)
3. Scores matching chunks with BM25 (FTS5 full-text search) — catches exact API names that semantic search may miss
4. Combines: `final = 0.7 × cosine + 0.3 × fts`
5. Deduplicates chunks from the same source with near-identical scores
6. Expands context by fetching adjacent chunks for high-scoring matches (score ≥ 0.72)
7. Returns results sorted logically by document position within each source

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | String | Yes | The search term (e.g. `JSONItem`, `FolderItem`, `database`). |
| `max_results` | Integer | No | Maximum number of matching sections to return. Default: 5. |
| `context_lines` | Integer | No | Number of lines of context before and after each match (keyword search only). Default: 10. |

#### `search_notes`

Searches the user's personal Xojo notes, written and curated in the [XDOX](https://github.com/o3jvind/XDOX) app. Notes capture the user's own conventions, hard-won fixes and project-specific knowledge — a complement to the official docs. All notes are searched regardless of which Xojo version is active. Notes marked as version-specific in XDOX and written for an older version are flagged `[possibly outdated — written for Xojo <version>]`; notes marked global (version-independent) are never flagged.

Requires the XDOX database (see discovery order above); against a legacy `xojo_rag.db` the tool responds gracefully that no notes database exists.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | String | Yes | The search term to look for in note titles and bodies. |
| `max_results` | Integer | No | Maximum number of notes to return. Default: 5. |

#### `lookup_class`

Looks up detailed documentation for a specific Xojo class, control, data type, or API by name. Returns the full structured reStructuredText reference including properties, methods, events, and examples.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `class_name` | String | Yes | The name of the class (e.g. `DesktopButton`, `JSONItem`, `FolderItem`, `String`). |

Automatically tries common prefixes (`Desktop`, `Web`) if the exact name isn't found.

#### `list_doc_topics`

Lists available Xojo documentation topics and pages from the `llms.txt` index. Use this to discover what documentation is available before looking up specific classes.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `filter` | String | No | Keyword to filter topics (e.g. `Desktop`, `database`, `networking`). If empty, returns all topics. |

### Docset Tools

These tools search third-party documentation from Dash/Zeal-style `.docset` bundles — the same format used by [Dash](https://kapeli.com/dash) (macOS) and [Zeal](https://zealdocs.org) (Windows/Linux), covering hundreds of languages, frameworks, and libraries via [Dash-User-Contributions](https://github.com/Kapeli/Dash-User-Contributions). Independent of the Xojo-specific documentation tools above — register one or more bundles with `--docset-path` (repeatable) and they're immediately searchable, no restart-time indexing required.

Two on-disk docset layouts are supported: a plain `Contents/Resources/Documents/` HTML tree, and Dash's space-saving `tarix.tgz` archive layout — the latter is extracted once into `~/Library/Application Support/dk.o3jvind.xmcp/docset-cache/` on first read and served from that cache afterward.

#### `list_docsets`

Lists the registered `.docset` bundles by name, with their entry counts. Call this first to discover available docset names before calling `search_docset` or `get_docset_entry`.

*No parameters.*

#### `search_docset`

Searches entry names (class, method, function, guide, etc.) across all registered docsets, or a single one via `docset_name`. Results are grouped by docset when searching all of them.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | String | Yes | The search term to look for (e.g. a class, method, or function name). |
| `docset_name` | String | No | Limit the search to one registered docset by name (as returned by `list_docsets`). If omitted, all registered docsets are searched. |
| `max_results` | Integer | No | Maximum number of matching entries to return per docset. Default: 10. |

#### `get_docset_entry`

Reads the full documentation content for a specific entry from a registered docset, as plain text (HTML stripped). Use `search_docset` first to find the exact `entry_name`.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `docset_name` | String | Yes | The registered docset to read from (as returned by `list_docsets`). |
| `entry_name` | String | Yes | The exact entry name to read (as returned by `search_docset`). |

### Debug Tools

These tools help diagnose runtime errors in Xojo apps by reading exception logs and system diagnostic output. For best results when building an app from scratch with XMCP, add an `App.UnhandledException` handler that writes to `/tmp/xmcp_debug.log`.

#### `get_debug_log`

Reads crash and exception info from `/tmp/xmcp_debug.log`. This file is written by `App.UnhandledException` handlers in Xojo apps that use the XMCP debug pattern. Call this after a crash or unexpected termination to retrieve exception details. The log is not cleared automatically and may contain data from a previous crash — use `clear: true` after reading to ensure the next crash produces a fresh log.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `clear` | Boolean | No | If true, deletes the log file after reading it. Default: false. |

#### `get_system_log`

Reads recent `System.DebugLog` output from the macOS unified log. Works for both debug builds (`AppName.debug`) and built apps (`AppName`).

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `process_name` | String | Yes | The process name to filter by. Debug builds use `AppName.debug`; built apps use `AppName`. Use `get_project_info` to find the project name. |
| `seconds` | Integer | No | How many seconds back to search the log. Default: 60, max: 3600. |

### Cost Awareness Tools

These tools estimate likely token cost before execution and suggest lower-cost approaches.

#### `estimate_request_cost`

Estimates expected token impact for a proposed request and optionally uses planned tool names to refine the estimate. Returns `LOW`, `MEDIUM`, or `HIGH`, with reasons and cheaper alternatives.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `request` | String | Yes | Natural-language request to estimate (for example: `Add a ListBox to Window1`). |
| `planned_tools` | String | No | Optional comma-separated tool names you expect to call (for example: `select_project_item,create_project_item`). |

### Disk-File Generation and Validation Tools

These tools generate or validate `.xojo_code`/`.xojo_window` `#tag` syntax directly on disk — no IDE socket call, so they work even when the Xojo IDE is closed. Both read their format rules (block ordering, `Flags`/keyword mapping, Constant `Default` escaping) from a machine-readable JSON block embedded in `usage-guide.md`, so a rule fix takes effect on the next tool call with no rebuild.

#### `scaffold_code_block`

Generates a correctly formatted `#tag` block (Method, Property, Constant, Event definition, Shared method, control event handler, or window event handler) for the caller to insert into a file directly, instead of hand-writing `#tag` syntax from memory.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `block_kind` | String | Yes | One of: `method`, `property`, `constant`, `event_definition`, `shared_method`, `control_event`, `window_event`. |
| `name` | String | Yes | Method/property/constant/event name, or the control name for `control_event`. |
| `visibility` | String | No | `public`, `protected`, or `private`. Applies to `method`/`property`/`shared_method`. Default: `public`. |
| `event_or_signature` | String | No | Event signature (e.g. `Pressed()`) for `control_event`/`window_event`, or parameter list for `event_definition`. |
| `constant_type` | String | No | For `constant` only: `String`, `Integer`, `Double`, `Boolean`, or `Color`. Default: `String`. |
| `default_value` | String | No | For `constant` only: the raw, unescaped default value — this tool escapes it automatically. |
| `target_file_type` | String | No | `xojo_code` or `xojo_window`. Informational only — escaping is identical for both. Default: `xojo_code`. |

#### `lint_project_file`

Validates a `.xojo_code` or `.xojo_window` file on disk for known structural errors: wrong `#tag` block ordering, `Flags`/keyword mismatches, unclosed or mismatched `#tag`/`#tag End` pairs, and unescaped characters in Constant `Default` values. Call this after editing a file directly on disk and before `revert_project`. Reports errors and warnings; never modifies the file.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | String | Yes | Absolute path to the `.xojo_code` or `.xojo_window` file to validate. |

### File Tools (opt-in)

Direct filesystem access for MCP clients with no file tools of their own (e.g. Claude Desktop). **Disabled by default** — start XMCP with `--enable-file-tools` to register them, bringing the tool count to 34 on macOS and 33 on Windows. Access is restricted to an allowlist of directories given via `--file-root` (comma-separated absolute paths, default `/tmp`); see [File tool sandbox](#file-tool-sandbox) below. If your MCP client already has file tools (Claude Code does), leave these off.

#### `write_file`, `read_file`, `hash_file`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | String | Yes (all three) | Absolute path to the file. Must be inside an allowed file root. |
| `content` | String | Yes (`write_file`) | Full text content to write; existing content is replaced entirely. |
| `expected_hash` | String | No (`write_file`) | MD5 or SHA-256 hex digest the file is expected to have right now (from `hash_file`). The write is refused if the file changed since then, so a concurrent edit is never silently discarded. |
| `offset` | Integer | No (`read_file`) | Character offset to start reading from. Default 0. |
| `length` | Integer | No (`read_file`) | Maximum characters to read. Default 0 (whole file). |
| `algorithm` | String | No (`hash_file`) | `md5` (default) or `sha256`. |

`read_file` returns content verbatim, with no added header — always safe to write straight back with `write_file`. `hash_file` streams in 1 MB chunks, so file size is not limited by available memory.

#### File tool sandbox

`--file-root` paths are lexically canonicalised (`.`/`..` resolved, duplicate slashes collapsed, macOS's symlinked `/tmp`, `/var`, `/etc` mapped to `/private`), then resolved through `realpath(3)` before comparison, so a symlink inside an allowed root can't be used to escape it. This narrows but doesn't eliminate the risk: the access check and the file open are separate syscalls, so a symlink swapped in between the two would still escape — Xojo has no `openat`-style primitive to close that gap fully.

## Resources

XMCP exposes MCP resources that AI clients can fetch at session start:

| URI                        | Name                | Description                                                                                        |
|----------------------------|----------------------|----------------------------------------------------------------------------------------------------|
| `file://usage-guide.md`    | XMCP Usage Guide     | AI-facing guide: capabilities, limitations, when to use IDE tools vs. direct file editing, and tips |
| `file://examples/<name>`   | Example: `<name>`    | One resource per file in `examples/` — reference templates for correct `.xojo_code`/`.xojo_window` structure |

Both `usage-guide.md` and `examples/` are distributed next to the XMCP binary and are plain files on disk — no rebuild required to change either. Compatible MCP clients (e.g. Claude Code) fetch them automatically via `resources/list` and `resources/read`.

## Adapting XMCP to your stack

XMCP ships configured for Xojo development: the default `usage-guide.md` biases the AI toward IDE tools and Xojo documentation, and `examples/` holds Xojo reference templates. Nothing about the underlying mechanism is Xojo-specific, though — three parts of XMCP are meant to be edited per project or per developer, not just per Xojo version:

- **`--docset-path`** — register any Dash/Zeal `.docset` bundle (see [Docset Tools](#docset-tools)) to make a language, framework, or library's documentation searchable alongside — or instead of — Xojo's own docs. A project mixing Xojo with an HTML/JS/CSS front end, for example, can register docsets for all three and search whichever is relevant.
- **`examples/`** — swap the reference templates for whatever the current language or project actually looks like. The mechanism (one MCP resource per file, auto-discovered from the folder) doesn't care what's in it.
- **`usage-guide.md`** — rewrite the guidance itself: which tools to prefer, in what order, for this particular mix of languages and conventions. It's plain text fetched into the AI's context at session start, not enforced code — treat it as a strong steer, not a guarantee, and back anything that must hold every time (a required namespace, a formatting rule) with a mechanical check like `lint_project_file` instead.

None of this requires touching XMCP's source — a `.xojo_project`-free setup (docsets only, no Xojo IDE running) works fine for the documentation tools; the IDE tools simply return connection errors until a project is opened.

## Architecture

```
XMCP
├── App                    — MCP server entry point, tool registration, docs auto-detection
├── IDECommunicator        — IPC socket communication with Xojo IDE (protocol v2)
├── SemanticSearch         — Optional hybrid search (vector + FTS5, neighbour expansion, cache)
├── Docset                 — Reads a single Dash/Zeal .docset bundle (SQLite index + HTML/tarix)
├── MCPKit/                — MCP protocol framework
│   ├── ServerApplication  — JSON-RPC stdin/stdout server loop
│   ├── Tool               — Base class for MCP tools
│   ├── ToolParameter      — Tool parameter definitions
│   ├── ToolArgument       — Parsed tool arguments
│   ├── ToolResult         — Success/Failure result type
│   ├── OptionParser       — CLI argument parsing
│   └── Option             — CLI option definition
└── Tools/                 — 31 MCP tool implementations
    ├── IDE tools (19)     — Control the Xojo IDE via IPC
    ├── Doc tools (3)      — Search and browse local Xojo documentation
    ├── Docset tools (3)   — Search third-party Dash/Zeal .docset bundles
    ├── Debug tools (2)    — Read crash logs and system diagnostic output
    ├── Cost tools (1)     — Estimate request token cost and alternatives
    └── Disk-file tools (2)— Generate/validate .xojo_code/.xojo_window syntax
```

### IDE Communication

XMCP connects to the Xojo IDE via an `IPCSocket` - a Unix domain socket on macOS and Linux, a TCP socket on `localhost` on Windows (see [The transport underneath](#the-transport-underneath)). It uses the **IDE Communicator Protocol v2**, where messages are NUL-terminated JSON objects:

1. On connect, sends `{"protocol": 2}` to upgrade to protocol v2
2. Requests are sent as `{"tag": "xmcp_3f9a1c2e_1", "script": "Print Location"}`
3. Responses arrive as `{"tag": "xmcp_3f9a1c2e_1", "response": "App.Constructor"}`
4. Tags correlate requests with responses for synchronous operation. Each tag is a random part chosen once per XMCP process plus a counter, so no two XMCP processes - a restarted one, or two clients at once - ever use the same tag

The `IDECommunicator` class handles connection management, tag generation, synchronous send/receive with configurable timeouts, and NUL-terminated message framing using direct `IPCSocket` communication.

#### One reply, several messages

A single request can be answered by **several messages under the same tag**. Measured against the IDE socket directly on macOS 15.7.5 and Windows 11, both Xojo 2026r2.1:

| Script | Reply |
|---|---|
| `Print "one"` | one frame, `{"response": "one"}` |
| `Print "one"` then `Print "two"` | **two frames**, one per `Print` |
| no `Print` at all | **no frame, ever** |
| `Print ""` | one frame, `{"response": {}}` |
| `Print "   "` (only whitespace) | the same as `Print ""` - the IDE collapses it; `Print "[   ]"` keeps its spaces |

An answer comes in parts - one per `Print`, then any compiler warning about the script - and the IDE sends each part the moment it is produced. So the parts of one answer can be a millisecond apart or minutes apart: a script that prints, then waits for a build or a dialog, then prints again, goes quiet in between (measured: a `Print`, 232 ms of work, then a second `Print` arrived 232 ms apart). Returning on the first part made the answer whichever part won the race - which is why a successful script sometimes reported only a warning.

XMCP keeps reading until the answer is complete and merges the parts. An error part is the answer, otherwise the output is, then a warning, then an empty reply. The other parts stay attached, which is how a tool reports the warning that *accompanied* a successful script rather than one or the other.

**How XMCP knows the answer is complete.** Not from a pause - a pause only means the script is busy. The `Print` XMCP appends to every script prints a marker unique to that request (`xmcp-end:` and the request's tag), and XMCP never passes the marker on. When the marker arrives, the script has run to its last line, and only a compiler warning can still follow: the IDE sends it just *after* the last `Print`. Measured against the raw socket on 2026r2.1, the warning follows 0.3-0.6 ms later on macOS and 0.03-0.35 ms later on Windows, and a 256 KB answer does not widen that. So after the marker XMCP waits 50 ms more - over 80 times the largest gap measured - and returns. A compile or runtime error ends the answer too, because the IDE stops the script there; XMCP then waits 250 ms after the error. Until one of the two arrives the script is still running, however much of its output has come in, and if the time limit runs out first the request is parked (below) rather than answered. Only a script that ends in a line continuation gets no marker - it cannot compile, so its answer is a compile error in practice - and for it the old rule stays: 250 ms after the first part that is not warnings alone. On an idle machine a typical call went from about 500 ms to about 300 ms; the IDE's own share is about 240 ms.

A reply that has reached its end marker is complete, even if all it holds is a warning - the script printed nothing else.

Because a script with no `Print` never answers, `SendAndReceive` appends one - the end-marker `Print` above - to every request before sending - in the transport rather than in each tool, so no tool can forget and a caller-supplied script cannot reintroduce the failure. Without it the request times out, its socket is parked as though the IDE were busy, and every later request is refused until the give-up timer expires - one `Print`-less script would block the session. An empty or whitespace-only script gets it too.

It is skipped in exactly one case: when the script's last line of code ends in a line continuation, where the appended line would be absorbed into it. Such a script cannot compile, and a compile error is itself a reply, so it cannot park. Deciding that is not "the last character is an underscore": measured on 2026r2.1, a comment can end in one (`// rename to foo_` is not a continuation), a name can end in one (`Var foo_ As Integer` is legal), and the space before it is optional (`+_` continues exactly like `+ _`). So a trailing comment is removed first - `'` or `//` outside a string literal, or a `Rem` line - and the underscore counts only when it does not end a name. When the test is unsure it appends: an appended sentinel can only change the compile error of a script that could not compile anyway, whereas a skipped one leaves a valid script unanswered.

The reply shapes XMCP recognises: a string (what the script printed), an empty object (it printed an empty string), `scriptError` - a **heterogeneous** array whose entries are `scriptCompilerError`, `scriptRuntimeError` or `scriptCompilerWarning`, so a warnings-only array means the script ran - and `buildError` with `errors` and `warnings`, plus `missingFiles`, `openErrors` and `loadError`. Every one of these keys in a reply is looked at, and a reply counts as clean only if none of them reports anything. A `buildError` counts as clean or as warnings only in the shape the IDE sends - an `errors` list, a `warnings` list, or both; any other shape is reported as an error, shown as it arrived, rather than being taken for a successful build. `openErrors` is not always an error: opening a project saved by an older Xojo answers with one whose entry says `"severity":"warning"` (an "IDE Version Conflict"), and the project does open. So an `openErrors` result counts as a warning only when it has exactly that measured shape - every entry holds only objects, and each object says severity "warning" and holds only plain values - and as an error otherwise, shown as it arrived. The rule is deliberately narrow: only one such result has been seen, passing a real error off as a warning is the worse mistake, and this way everything accepted as a warning can be shown in full. Script error line numbers are reported one lower than the IDE sends them, because the IDE wraps every script in a line of boilerplate before compiling it. A runtime error is sent with an empty message and line 0; XMCP says so in words rather than showing the bare error type.

**Every IDE tool reads a reply through the same classifier** - `ReplyKind`, `ReplyDiagnostics` and `ReplyWarnings` in `IDECommunicator`. `run_ide_script`, `build_project`, `run_project` and `analyze_project` call it directly; fourteen more go through `RunScript` - `set_code`, `constant_value`, `get_code`, `select_project_item` and nine others, plus `get_project_info`; `revert_project` uses `ReplyDiagnostics` for its own checks, and three of its helpers otherwise only confirm that a reply is a string, treating anything else as "could not read it". Before this, `RunScript` failed on any `scriptError` - warnings included - with a raw JSON dump, `get_project_info` reported one as *success*, and `revert_project` kept a private copy that treated a warning as an error.

Warnings surface differently depending on whose script it is. `run_ide_script` sends the caller's own script, so a warning is about their code and is reported with the output. The other tools send scripts XMCP generates, so a warning is a flaw in XMCP rather than anything the caller can act on - `get_selected_text`, for one, draws a precision warning on every call from its own `Str()` - and for most of them the result *is* data: selected text, a constant's value, a list of items. Appending a diagnostic would corrupt it. Those tools therefore report a warning only when the script printed nothing, and log it otherwise.

Two comparison rules follow from the same distinction. A tool's own guard clause prints exactly `ERROR:` at the very start, so `RunScript` tests for that prefix case-sensitively and untrimmed - `BeginsWith` is case-insensitive by default in this Xojo version, and data that merely begins `Error:` is data. And emptiness is tested exactly wherever the value is data (`MergeReply`, `RunScript`, `run_ide_script`), but trimmed where it is a protocol reply (`build_project`, `run_project`, `analyze_project` judging whether a build printed an error or nothing). With the IDE collapsing whitespace-only output itself, neither choice changes a reachable result today; the rule is there so that a future change does not have to rediscover it.

#### When the IDE does not answer

The IDE runs scripts one at a time on its main thread, so during a build - or behind a modal dialog - it answers nothing until it is done, then answers everything that queued up, on the connections the requests arrived on.

A socket whose request timed out is therefore **not closed**. On macOS and Linux the IPCSocket is a Unix domain socket, and the IDE's later write into a closed peer raises `SIGPIPE`, which the Xojo IDE does not ignore: it dies mid-build, with no crash report. The socket is parked open instead, and released once its answer is complete, by the same test as above - its end marker, or an error that stopped the script, or for a script with no marker a part that is not warnings alone - **and nothing more has arrived for 250 ms**; or once the IDE has closed the connection, or it can no longer be read from, or it has been parked for two hours. A pause on its own does not release it: a script waiting on a second dialog is still running, and a part meant for another request says nothing about this one.

Whenever there is a chance the IDE has already received the request, XMCP keeps the connection open and does not send the request again - sending it again could make the IDE run the same script twice. That covers a request that times out - including one whose output has started to arrive but whose script has not finished - an answer that turns out to belong to a different request, a connection that fails while XMCP is reading from it, and a request that fails halfway through being sent. If the IDE closes the connection before it has finished answering, XMCP stops waiting at once instead of at the time limit, and does not send the request again either: the IDE may already have run it. (On macOS, retrying "on another path" would usually reach the very same IDE, because two of the paths XMCP tries, `/tmp` and `/private/tmp`, are the same place.)

**Quitting Claude Code while a request is parked can crash the Xojo IDE.** A request is *parked* when the IDE takes longer than XMCP's time limit to answer it: instead of closing the connection, XMCP keeps it open until the answer arrives, for the reason above. Quitting or restarting Claude Code stops XMCP, stopping XMCP closes that connection, and when the IDE finally answers over the closed connection, it crashes. So before you quit or restart, let the IDE finish - wait for the build, or click the dialog. The message XMCP gives when a request is parked, and the one it gives when it turns down a new request because one is still parked, both say this. The AI in your session reads those messages, so it can remind you.

XMCP cannot yet prevent this itself. We tested the two ways a program can stop it:

1. **Claude Code stops XMCP with a signal.** Claude Code's own logs show that it stops a server by first sending it an interrupt signal. XMCP stops at once on that, so it has no chance to wait for the IDE. (The same logs show that when another server was still running a tenth of a second later, Claude Code followed up with a termination signal; XMCP has never needed the second one.)
2. **XMCP does not notice when a program simply stops talking to it.** Some programs stop a server not with a signal but by closing the connection they send it requests on. We tested this on macOS: XMCP does not notice, and carries on running until something else stops it. So there is no moment there for it to step in and wait either. This is an older problem, unrelated to the IDE work, listed below to be fixed on its own.

We did try adding a wait at the point where XMCP shuts down, and took it out again. The tests above showed that point is never reached, so the code could never run, and leaving it in would have suggested a protection that does not exist.

While one request is parked, new ones are turned down rather than sent, and the message names the request that is still waiting. A new request sent behind a busy IDE would only time out too, and the error would wrongly say the IDE did not answer, when in fact it is still working.

#### Decisions and known limits

The choices made in this work, and the problems we know about and have deliberately left for later.

- **A slow request's connection is kept open, not closed.** Closing it while the IDE is still working is what used to crash the IDE. The cost is that while it is held, no other program can talk to the IDE, because the IDE accepts only one connection at a time. To keep that short, XMCP checks for the answer continuously whenever it is otherwise idle, not only when the next request comes in.
- **After two hours XMCP gives up and closes the connection anyway.** If the IDE answers after that - a build longer than two hours, or a dialog left open all afternoon - it will crash. Without a limit, a request the IDE never answers would block every other program from the IDE for as long as XMCP runs. Two hours is longer than any build we have seen.
- **Once an answer is complete, the connection is closed.** Complete means its end marker has arrived, or an error that stopped the script. After the marker XMCP waits 50 ms for the compiler warning the IDE sends just after it; if a warning ever came later than that, the IDE would be writing to a closed connection. The largest gap measured is 0.6 ms. The alternative, keeping every connection open after it has been answered, would block other programs after every request.
- **Errors still take the longer wait.** A compile or runtime error stops the script before the end marker, so XMCP waits 250 ms after the error before closing. They could stop early too - measured, a runtime error and any warning arrive together in one frame - but errors are the uncommon case, and it is left as a possible improvement rather than widening this change.
- **A value that really begins with `ERROR:` reads as a failure.** The tools' guard clauses signal a failure by printing `ERROR:` at the start of their output, so a constant, description or selected text whose own value starts with exactly `ERROR:` - capitals, colon, at the very start - is reported as a failure too. `Error:` or anything else is data. Telling the two apart would mean changing how each of those tools reports a failure, which is outside this change.
- **While one request is waiting, new ones are turned down, not queued.** A queued request would only time out behind the slow one and report the wrong reason. The refusal names the request that is still waiting.
- **Quitting Claude Code while a request is waiting is warned against, not prevented.** The section above explains why prevention is not possible yet.
- **For later consideration (A′): let XMCP survive Claude Code's stop signals while a request is waiting.** XMCP could ask the operating system to ignore those two signals for as long as a request is waiting, and go back to normal as soon as the IDE answers. We have not done it because we do not know what Claude Code does when a program ignores its stop signals. If it then force-stops XMCP, nothing is lost compared with today. If it gives up and carries on, the IDE is protected. But if it waits for XMCP to finish, quitting Claude Code would seem to freeze until the IDE answers - possibly for up to two hours, which is worse than the crash. That has to be tested before deciding. It also only works once XMCP can tell that Claude Code has gone (the next point); otherwise it would never know when to finish and exit.
- **To fix separately: XMCP does not notice when the connection it receives requests on is closed.** It then keeps running indefinitely after being stopped that way. It predates this work, and fixing it is a precondition for A′.
- **Windows keeps the same precautions, although the IDE does not crash there.** On Windows XMCP reaches the IDE over a local network connection instead of a socket file. Tested on 2026r2.1: with XMCP killed while a request was waiting, the IDE answered into the closed connection and carried on - same process, still answering scripts - both for a short answer and for a 256 KB one. That is why the warnings say "macOS and Linux". The precautions stay anyway: an answer owed to a connection that has gone away is handed to the *next* client that connects, ahead of that client's own answer and with its original tag (measured against the raw socket), so keeping the waiting connection open is what keeps a late answer where it belongs, and turning new requests down while the IDE is busy is right on every platform. Tags are unique per XMCP process for the same reason: with the old per-process counter, a second XMCP's first request took the first one's late answer for its own - reproduced on Windows - and with unique tags the same test returns the right answer.
- **Some cases cannot be tested from outside, so they were checked by reading the code.** An answer arriving for a different request, a connection failing while XMCP is reading from it, and a request failing halfway through being sent cannot be made to happen on demand. In each case XMCP now keeps the connection open and does not resend the request - the same behaviour the timeout tests check on both platforms.
- **`debug_control` and `stop_project` report success even when no debug session is running.** That was already so before this work, is unchanged by it, and belongs with a later change to the run, build and stop tools.

For each IDE request, XMCP tries the last successful socket path first, then every candidate path for the platform. If all attempts fail, the tool returns a detailed connection/timeout error naming every path it tried.

#### The transport underneath

The IDE builds its socket path by appending `XojoIDE` - or the value of `XOJO_IPCPATH` - to the first writable temporary directory it finds. Xojo documents that search as two rungs ([IDE Communicator](https://documentation.xojo.com/topics/build_automation/ide_communicator.html), expanded in 2026r2.1 for [issue #68115](https://tracker.xojo.com/xojoinc/xojo/-/work_items/68115)):

1. `/tmp` - macOS and Linux only
2. `SpecialFolder.Temporary` - all platforms; `C:\Users\<user>\AppData\Local\Temp\` on Windows

`Platform.IPCSocketPaths` probes a slightly wider chain, mirroring `FindIPCPath` in Xojo's shipped IDECommunicator v2 example (the client Xojo ships for talking to its own IDE). The extra rungs cost nothing - a folder that is not writable is never added, and a candidate nothing listens on is ruled out by a short connect timeout:

| Rung | macOS / Linux | Windows |
|------|---------------|---------|
| 1 | `/tmp` | `C:\tmp` (rarely exists) |
| 2 | `/var/tmp` | `C:\var\tmp` (rarely exists) |
| 3 | `SpecialFolder.Temporary` | `%LOCALAPPDATA%\Temp` <- **in practice, this one** |
| 4 | `SpecialFolder.Home` | `%USERPROFILE%` (follows OneDrive when active) |

Rungs 1 and 3 are the documented ones; 2 and 4 come from the example client and rarely exist.

The socket file name is `XojoIDE`, or the value of `XOJO_IPCPATH` when set - which is how you address one specific IDE when several are running. That value is a bare **name** appended to the temporary directory, not a path, and Xojo accepts only `a-z`, `A-Z`, `0-9` and underscore; anything else is ignored rather than passed through.

> Set `XOJO_IPCPATH` in the environment that launches **XMCP**, not only the one that launches the IDE. XMCP reads it from its own process environment, so for Claude Code that means the MCP server entry, not your shell.

Two platform differences matter:

- **Windows endpoints have no filesystem entry**, because on Windows an `IPCSocket` is not a file at all but a TCP socket on `localhost` whose port is derived from the path string. `FolderItem.Exists` on the socket path is therefore always `False` there, even while the IDE is listening, so it must never gate the connect. XMCP keeps the existence check as a fast path on macOS and Linux only, and on Windows rules a candidate out with a short (1.5 s) connect timeout instead.
- **The path is per-user.** `SpecialFolder.Temporary` resolves under the running account, so XMCP must run as the same Windows user as the IDE. When no listener is found, the error message lists every path that was tried.

### Documentation Auto-Detection

On startup, XMCP scans the platform's Xojo application-data folder (`~/Library/Application Support/Xojo/Xojo/` on macOS, `%APPDATA%\Xojo\Xojo\` on Windows) for the newest Xojo version directory that contains `Documentation/llms-full.txt`. This file (along with `llms.txt` and `_sources/*.rst.txt`) is available via **Xojo IDE → Preferences → General → Install Local Documentation** and is intended specifically for LLM consumption.

## Known Limitations

- **`get_system_log` is macOS-only** — it reads the macOS unified log, which has no equivalent elsewhere, so it is not registered on other platforms. Every other tool works on both macOS and Windows.
- **Linux is untested** — the path resolution covers it, but nobody has run XMCP there.
- **IDE tools require an open project** — the Xojo IDE scripting socket must be available and a project must be loaded.
- **Documentation tools require local docs** — depend on `llms-full.txt`, `llms.txt`, and `_sources/*.rst.txt` files shipped with the Xojo IDE.
- **Docset tools require registered bundles** — `list_docsets`, `search_docset`, and `get_docset_entry` return an error until at least one `--docset-path` is supplied; a docset shipped as a `tarix.tgz` archive is extracted to a local cache on first read, which can take a few seconds for a large bundle.
- **`get_code`, `set_code`, `get_selected_text`, `set_selected_text` require a method or property to be active** — these tools operate on the code editor view. If the selected item in the Navigator is a class, module, or folder (not a method, property, or other code item), they return an error: `No code editor is active. Navigate to a method or property first.`
- **`select_project_item` navigates to classes and folders, not individual methods or events** — the Xojo IDE scripting API (`SelectProjectItem`) can navigate to top-level items and classes, but not to individual methods, properties, or event implementations. `list_project_items` also does not list events. To read or write code for a specific method or event, use `get_code` or `set_code` with the full dot-separated path — XMCP navigates automatically before reading/writing.
- **IPC socket timing after navigation** — the Xojo IDE briefly closes its IPC socket (~2–3 seconds) after certain navigation operations. XMCP handles this with automatic retries (up to 5 × 1 second), so tools work reliably, but sequential IDE calls may take a few seconds longer after navigation.
- **Parallel tool calls are not supported** — the Xojo IDE accepts only one IPC connection at a time. MCP clients that send parallel tool calls (e.g. Claude Code in some modes) may see connection errors on concurrent requests. Sequential tool calls work reliably.

## Acknowledgments

- [MCPKit](https://github.com/gkjpettet/MCPKit) by Garry Pettet — the Xojo MCP framework that XMCP is built on

## License

MIT
