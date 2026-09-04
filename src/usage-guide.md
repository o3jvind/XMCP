# XMCP Usage Guide for AI Assistants

This file is automatically loaded as an MCP resource when you connect to XMCP. It describes XMCP's capabilities, known limitations, and how to choose the right approach for each task. You can edit this file to add project-specific notes or customise the guidance.

---

## Prerequisites — before using any XMCP tools

**XMCP cannot start Xojo IDE.** All tools communicate via a macOS domain socket (`/tmp/XojoIDE`) that Xojo IDE creates when it launches. If the IDE is not running, every tool call will fail with "IPC socket not found".

**The user must:**

1. Start Xojo IDE manually
2. Open the project they want to work with (File > Open) — XMCP cannot open projects
3. Wait a few seconds after launch before the IPC socket is ready — if tools fail immediately after IDE start, ask the user to wait and retry

**Do not attempt any XMCP tool calls until the user confirms that Xojo IDE is open and the project is loaded.**

---

## What XMCP can do

XMCP gives you direct control over the Xojo IDE via 25 tools:

- **Navigate**: `list_project_items`, `get_current_location`, `select_project_item`
- **Read/write code**: `get_code`, `set_code`, `get_selected_text`, `set_selected_text`
- **Build and run**: `build_project`, `run_project`, `stop_project`
- **Save and analyze**: `save_project`, `analyze_project`
- **Debug sessions**: `debug_control`
- **Create items**: `create_project_item`
- **Inspect and modify**: `get_item_description`, `constant_value`, `get_project_info`, `revert_project`
- **IDE scripting**: `run_ide_script` (escape hatch for anything not covered)
- **Documentation**: `search_docs`, `lookup_class`, `list_doc_topics`
- **Debugging**: `get_debug_log`, `get_system_log`
- **Cost estimation**: `estimate_request_cost` — call this proactively before broad or documentation-heavy tasks to check whether the approach is likely to be expensive, and to get suggestions for cheaper alternatives

### Optional file tools (opt-in)

Three additional tools — `write_file`, `read_file`, and `hash_file` — provide direct filesystem access for MCP clients that lack built-in file tools (e.g. Claude Desktop). They are **disabled by default** and only registered when the server is started with `--enable-file-tools`, bringing the tool count to 28.

When enabled, access is restricted to an allowlist of directories given via `--file-root` as comma-separated absolute paths (default: `/tmp`). Paths are lexically canonicalised before checking: `.` and `..` segments are resolved, duplicate slashes collapsed, and the macOS symlinked prefixes `/tmp`, `/var` and `/etc` are mapped to their `/private` equivalents. Requests outside the allowed roots fail with an "Access denied" result. Known limitation: symlinks *inside* an allowed root are not resolved and can point outside it.

- `write_file` — write UTF-8 text to a file (whole-file replace); parent directory must exist
- `read_file` — read UTF-8 text; `offset`/`length` are **character** offsets, so chunked reads never split a multibyte sequence
- `hash_file` — MD5 or SHA-256 hex digest, streamed in 1 MB chunks (arbitrarily large files supported)

Typical Claude Desktop configuration:

```json
"args": ["--enable-file-tools", "--file-root", "/tmp,/Users/you/GitHub"]
```

---

## Trust model — XMCP is a full-trust local bridge

XMCP runs as a local process that drives a real Xojo IDE on the user's machine. It is **not** a sandbox. In particular:

- **`run_ide_script` is an unrestricted escape hatch.** It executes arbitrary Xojo IDE scripting code with the IDE's full authority — read or write any file the IDE can reach, modify project code, build, run, install, or shell out via the IDE's scripting surface.
- **`set_code`, `create_project_item`, `build_project`, `run_project`, `revert_project`, `save_project`, `analyze_project`, `debug_control`** all mutate the user's project, run user-authored code, or discard work. None of them ask the IDE for confirmation.
- **Direct file edits** to `.xojo_code` / `.xojo_window` / `.xojo_project` files happen at the filesystem layer with the user's normal write permissions.

This is appropriate for the intended use case: a single trusted MCP client (Claude Code) on the developer's own workstation acting on their explicit instructions. It is **not** appropriate to expose XMCP to an untrusted client or a multi-tenant context — there is no privilege separation, no per-tool capability check, and no audit trail beyond `/tmp/xmcp_debug.log`.

If you (the AI assistant) are about to take a destructive or hard-to-reverse action (build, run, revert, overwriting code, mass file edits), confirm with the user first, even when a tool will technically succeed without asking. The trust the user extends to XMCP is the trust they extend to you.

---

## Starting work on a new project — recommended first steps

When you connect to a new Xojo project via XMCP:

1. Call `get_project_info` to confirm the IDE is connected and get the project directory path
2. Check whether `App` already has an `UnhandledException` handler (see below)
3. **If not, proactively offer to add it** — this is essential for diagnosing crashes in built apps

---

## Crash reporting — add UnhandledException to App

In built apps, runtime exceptions are silent unless you add an `UnhandledException` handler. Without it, crashes produce no output visible to XMCP.

Add this to `App.xojo_code` (before the `#tag ViewBehavior` section):

```xojo
#tag Event
    Sub UnhandledException(error As RuntimeException)
      Var msg As String = "Error: " + error.Message + EndOfLine
      msg = msg + "Error Number: " + Str(error.ErrorNumber) + EndOfLine
      If error.Stack <> Nil Then
        msg = msg + "Stack:" + EndOfLine
        For Each frame As String In error.Stack
          msg = msg + "  " + frame + EndOfLine
        Next
      End If

      Var f As New FolderItem("/tmp/xmcp_debug.log")
      Var stream As TextOutputStream = TextOutputStream.Open(f)
      stream.Write(msg)
      stream.Close
    End Sub
#tag EndEvent
```

After adding, ask the user for permission to call `revert_project` to reload the project.

Once in place, use `get_debug_log` after a crash **in a built app** to retrieve the full exception message and stack trace. Without this handler, `get_debug_log` will always return empty — there is nothing to log.

**`UnhandledException` does NOT fire in debug mode.** The Xojo debugger intercepts all exceptions before they reach this handler — they appear in the IDE debugger instead. This handler is only useful in built apps.

**The log file is not cleared automatically.** It may contain data from a previous crash rather than the current one. Always call `get_debug_log` with `clear: true` after reading, so the next crash produces a fresh log.

---

## How to edit code

**Always edit source files directly on disk** — for both `.xojo_code` and `.xojo_window` files. This is the primary editing path, not a fallback.

The workflow is exactly two steps:
1. Edit the file on disk (using your client's own `Edit`/`Write` tools)
2. Call `revert_project` to reload it in the IDE

**Do not route edits through `run_ide_script` + `DoShellCommand` + Python/sed.** That path exists as a last resort; it adds fragile quoting, whitespace-sensitivity, and encoding failure modes that the direct approach avoids entirely. If you find yourself writing a shell script to modify a Xojo source file, stop and use your file editing tools instead.

**Do not use `set_code` to write code** — it only covers top-level navigable items, cannot target individual methods, and does not work at all for `.xojo_window` files.

The only exception is when the user explicitly asks you to read or edit code they have selected in the IDE. In that case, `get_code` and `set_code` without a location parameter work reliably for reading the current selection or replacing it. After writing with `set_code`, always remind the user to save the project (Cmd+S) — `set_code` writes to the IDE editor but does not save to disk.

---

## Direct file editing — how to do it

Reference examples of all common file structures are in the `examples/` folder next to this file. Use them as templates when creating or editing `.xojo_code` and `.xojo_window` files.

| File type | Used for | Example |
| --- | --- | --- |
| `<Name>.xojo_code` | Class, module, interface, app-level code | `MyClass.xojo_code`, `App.xojo_code` |
| `<Name>.xojo_window` | Window UI layout, controls, window events, control events | `MainWindow.xojo_window` |
| `<Name>.xojo_menu` | Menu bar definition (separate file, not embedded in window) | `MainMenuBar.xojo_menu` |
| `<Name>.xojo_project` | Project manifest — lists all files and build settings | edit sparingly |

1. **Find the project directory**
   Call `get_project_info` — it returns a `Project Directory:` line with the full path.

2. **Find the right file**
   - Classes, modules, interfaces, app-level code → `<ClassName>.xojo_code`
   - Window UI, controls, and event handlers → `<WindowName>.xojo_window`
   - Menu bars → `<MenuBarName>.xojo_menu`
   - Project manifest → `<ProjectName>.xojo_project`

3. **Edit the file**
   `.xojo_code` and `.xojo_window` are plain text with `#tag` markers. Follow the existing structure exactly — Xojo is sensitive to block ordering (see below).

   Window-level event handlers go in `#tag WindowCode`:

   ```xojo
   #tag WindowCode
       #tag Event
           Sub Opening()
             ' your code here
           End Sub
       #tag EndEvent
   #tag EndWindowCode
   ```

   Control event handlers (e.g. a `DesktopButton`'s `Pressed` event) go in a `#tag Events ControlName` block *after* `#tag EndWindowCode`:

   ```xojo
   #tag Events Button1
       #tag Event
           Sub Pressed()
             MessageBox("Hi")
           End Sub
       #tag EndEvent
   #tag EndEvents
   ```

   Menu item handlers go in `#tag WindowCode` as `#tag MenuHandler` blocks:

   ```xojo
   #tag MenuHandler
       Function FileOpen() As Boolean Handles FileOpen.Action
         ' handle File > Open
         Return True
       End Function
   #tag EndMenuHandler
   ```

4. **Reload in the IDE**
   Ask the user for permission first, then call `revert_project`. The reload is destructive to any unsaved IDE-side edits — saving them first would overwrite the disk changes we just made, so the tool deliberately does not save.

---

## Xojo file structure rules

### Block ordering in `.xojo_code` files

Blocks **must** appear in this order or Xojo will reject or silently corrupt the file:

**Class file:**
1. `#tag Event` definitions (custom events the class can raise)
2. `#tag Method` blocks (Constructor first by convention, then others)
3. `#tag Property` blocks
4. `#tag Constant` blocks
5. `#tag Note` blocks
6. `#tag ViewBehavior` — **always last, never add anything after it**

**Module file** (same as class but no `#tag Event`):
1. `#tag Method` blocks
2. `#tag Constant` blocks
3. `#tag Property` blocks
4. `#tag Note` blocks
5. `#tag ViewBehavior` — **always last**

**Window file:**
1. `#tag DesktopWindow` … `#tag EndDesktopWindow` (control layout block)
2. `#tag WindowCode` … `#tag EndWindowCode` (window events, menu handlers, methods, properties)
3. `#tag Events ControlName` … `#tag EndEvents` blocks (one per control that has events)
4. `#tag ViewBehavior` — **always last**

### Access modifier flags

Every `#tag Method` and `#tag Property` line carries a `Flags = &hXX` value. The flag **and** the keyword in the declaration line must match — both are required.

| Flag | Modifier | Applies to |
| --- | --- | --- |
| `&h0` | Public | Methods, Properties |
| `&h1` | Protected | Methods, Properties |
| `&h21` | Private | Methods, Properties |

The keyword goes on the declaration line inside the block:

```xojo
#tag Method, Flags = &h1
    Protected Function Helper() As String
      Return "x"
    End Function
#tag EndMethod

#tag Property, Flags = &h21
    Private mName As String
#tag EndProperty
```

**Constants use a different format** — all metadata is on the `#tag Constant` line itself, nothing inside the block:

```xojo
#tag Constant, Name = kMaxItems, Type = Integer, Dynamic = False, Default = "100", Scope = Public
#tag EndConstant

#tag Constant, Name = kSecret, Type = String, Dynamic = False, Default = "", Scope = Private
#tag EndConstant
```

Valid `Scope` values for constants: `Public`, `Protected`, `Private`. Valid `Type` values: `String`, `Integer`, `Double`, `Boolean`, `Color`.

### Shared (class-level) methods

Add the `Shared` keyword before `Function` or `Sub`. The flag value is identical to instance methods:

```xojo
#tag Method, Flags = &h0
    Shared Function Create(name As String) As MyClass
      Return New MyClass(name)
    End Function
#tag EndMethod
```

Called as `MyClass.Create("foo")` — no instance needed.

### Custom event definitions

A `#tag Event` block inside a **class body** (not a window) *defines* an event the class can fire. It contains only the signature — no body:

```xojo
#tag Event, Description = "Fired when the count changes."
    Sub CountChanged(newCount As Integer)
    End Sub
#tag EndEvent
```

Raise it from within the class with `RaiseEvent CountChanged(mCount)`. Consumers implement the handler via `AddEventImplementation` in the IDE, or by editing the `.xojo_window` file directly.

### Non-singleton windows (`ImplicitInstance = False`)

Windows that can be opened multiple times (editor dialogs, detail panels) use `ImplicitInstance = False` in the control block. They must be instantiated explicitly:

```xojo
Var w As New DetailWindow
w.LoadItem("Title", "Body text")
w.Show        ' non-blocking — caller continues
' -- or --
w.ShowModal   ' blocks until window closes
```

The `DetailWindow.xojo_window` example in `examples/` demonstrates this pattern including a `LoadItem()` method, `LayoutControls()`, and `Default`/`Cancel` button flags.

### Note blocks

`#tag Note` blocks are plain-text documentation embedded in the file. They appear before `#tag ViewBehavior`:

```xojo
#tag Note, Name = DesignNotes
    Explain design decisions, invariants, or usage here.
    Free-form text — no special markup needed.
#tag EndNote
```

### String constants in `.xojo_window` files

Constants in `.xojo_window` files use a different escape format than `.xojo_code` files. The IDE encodes the `Default` value like this:

| Character | `.xojo_window` encoding |
| --- | --- |
| `"` (double quote) | `\"` |
| `'` (single quote) | `\'` |
| `=` | `\x3D` |
| `,` (comma) | `\x2C` |
| newline | `\n` |
| Non-ASCII (e.g. `°`) | UTF-8 bytes e.g. `\xC2\xB0` — **not** `\uXXXX` |

Note: `.xojo_code` files use `""` for embedded double quotes — the `\x3D`/`\x2C`/`\'` rules **only** apply to `.xojo_window`.

**Never write HTML, JavaScript, or any string containing commas or single quotes directly into a constant `Default` value in a `.xojo_window` file on disk.** Missed characters silently truncate the value with no error.

Use one of these approaches instead:

1. **Paste via the IDE** — enter the raw value in the constant's Default Value field in the Xojo IDE, let the IDE escape it, then save (Cmd+S).
2. **Build at runtime** — assemble the string in a Xojo method using string concatenation. This avoids escaping entirely and is more readable.

---

## IDE tool limitations to be aware of

### Never use `DoCommand "Insert..."` to add controls to windows

Using `DoCommand "Insert..."` commands (e.g. `DoCommand "InsertDesktopButton"`) to add UI controls to a window **disconnects the Xojo IDE's IPC socket**, making all subsequent XMCP tool calls fail until the IDE is restarted.

Always add controls by editing the `.xojo_window` file directly on disk instead. Use `examples/Window1.xojo_window` as a reference for the correct control block format and event handler structure.

### `select_project_item` cannot navigate to methods or events

The IDE scripting API can navigate to top-level items, classes, modules, and windows — but not to individual methods, properties, or event implementations. Edit the source file directly on disk instead.

`list_project_items` also does not list events — only methods, properties, and constants appear as children.

### Documentation tools — use search_docs and lookup_class, not list_doc_topics

- `search_docs` — search guides and tutorials by natural-language query. Use this first for any conceptual or how-to question.
- `lookup_class` — look up a specific class or method in the API reference.
- `list_doc_topics` — returns the full documentation index (143,000+ characters). **Never call this to find information** — it wastes tokens and requires multiple slow read passes. Use `search_docs` instead. Only call `list_doc_topics` if the user explicitly asks for a topic overview.

### IDE scripting quirks (run_ide_script)

- `SelectProjectItem` returns a Boolean — always capture the return value: `Dim r As Boolean = SelectProjectItem("Window1")`
- `GetProjectItem` does not exist in the IDE scripting language — using it causes a compile error
- Avoid declaring variables as `ProjectItem` — it is a method name in the scripting language, not a type

### Parallel tool calls are not supported

The Xojo IDE accepts only one IPC connection at a time. Always use sequential tool calls.

### IPC socket timing after navigation

After certain navigation operations, the IDE briefly closes its IPC socket (~2–3 seconds). XMCP retries automatically. If a tool times out immediately after navigation, retry once.

---

## Running and building — rules and workflow

### Never act without explicit user request

- **Never call `build_project` unless the user explicitly asks you to build**
- **Never call `run_project` unless the user explicitly asks you to run**
- **Never call `revert_project` without asking the user first** — it discards any unsaved IDE-side edits. (XMCP cannot save them first: that would overwrite the disk changes the reload is meant to ingest.)

Always wait for the user's answer before proceeding. Asking a question and then acting anyway defeats the purpose.

### Recommended workflow when the user asks to build

1. **Offer to run first**: Before building, offer to call `run_project` to catch syntax errors. **Note:** Runtime errors will only be visible to the user in the Xojo IDE debugger — not to XMCP.
2. **Run and ask for feedback**: After `run_project` returns, always ask the user if they see any errors or exceptions in the IDE — XMCP cannot see runtime behaviour in debug mode.
3. **Only build if run succeeds** — or if the user explicitly wants to build anyway.

### What run_project and build_project can and cannot see

| | `run_project` | `build_project` |
| --- | --- | --- |
| Syntax errors | ✓ Returns error | ✓ Returns error |
| Runtime exceptions (debug mode) | ✗ Invisible — IDE debugger catches them | — |
| Runtime exceptions (built app) | — | ✗ Invisible without `UnhandledException` |
| Build output on disk | — | ✓ Verify `.app` exists after build |

**After `run_project` returns "Project launched in debug mode"**: always ask the user if the app is behaving correctly and if they see any exceptions in the IDE debugger.

**Note:** `run_project` catches syntax errors. Runtime exceptions are visible to the user in the Xojo IDE debugger — but not to XMCP.

### save_project — when and why to call it

`set_code` writes to the IDE's in-memory editor but does **not** save to disk. After writing code with `set_code`, call `save_project` before building or running so that the changes are persisted. (Direct file edits on disk are already saved; `save_project` is only needed after `set_code`.)

### analyze_project — check before building

Use `analyze_project` to catch errors and warnings without triggering a full build. It is faster than `build_project` and useful for a quick sanity check after editing code.

- **`scope="project"`** (default) — analyzes the entire project. Use before a build.
- **`scope="item"`** — analyzes only the currently selected item. Use for a fast check on the item you just edited.

Warnings return as success (they don't block building). Errors return as failure with a formatted list identical to `build_project` output.

**Recommended pre-build workflow:**
1. Edit code (direct file edit or `set_code`)
2. `save_project` (if you used `set_code`)
3. `analyze_project` — fix any errors before proceeding
4. `run_project` or `build_project`

### debug_control — stepping through a debug session

When a debug session is active (started with `run_project`) and the app is paused at a breakpoint or exception, use `debug_control` to drive execution:

| Action | Equivalent IDE action |
| --- | --- |
| `step_over` | Step over the current line |
| `step_into` | Step into the method call on the current line |
| `step_out` | Step out of the current method |
| `resume` | Continue running until the next breakpoint or pause |
| `pause` | Pause a running debug session |

**Note:** XMCP cannot read variable values, set breakpoints, or inspect the call stack — those require the Xojo IDE debugger UI. `debug_control` only drives execution flow.

### build_project uses the IDE's Build Settings

`build_project` takes no parameters — it builds using whatever target platforms the user has configured in the IDE's Build Settings (`BuildMac`, `BuildWin32`, etc.). On success it returns "Build succeeded."; on failure it returns the list of build errors. The success message does not include a path, so to confirm the build location, check the project's `Builds - <ProjectName>/` directory.

### Debug mode vs. built app — exception visibility

| Scenario | Exceptions visible to XMCP? | Where to look |
| --- | --- | --- |
| `run_project` (debug mode) | No | User sees them in Xojo IDE debugger |
| Built app with `UnhandledException` | Yes — via `get_debug_log` | `/tmp/xmcp_debug.log` |
| Built app without `UnhandledException` | No | Nowhere — add the handler |

---

## Tips for working effectively with XMCP

- Call `get_project_info` early to understand the project structure and get the directory path
- Use `list_project_items` to explore the project tree before navigating
- Use `run_ide_script` to run arbitrary IDE scripting commands when no dedicated tool exists
- Use `get_system_log` to retrieve `System.DebugLog` output — works for both debug builds (`AppName.debug`) and built apps (`AppName`)

---

*This file can be edited to add project-specific notes, custom conventions, or additional guidance for your AI assistant.*
