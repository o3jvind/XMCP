**XMCP + Claude Desktop — Setup and Usage Tutorial**  
A concise guide to controlling the Xojo IDE from Claude Desktop using XMCP, with the folder structure for skills and the workflow that works reliably in practice.  
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANklEQVR4nO3OQQmAABRAsSeYxZw/lieLGMACBrCCNxG2BFtmZquOAAD4i3Ot7mr/egIAwGvXA6fGBdgoVMwYAAAAAElFTkSuQmCC)  
**1. What XMCP Is**  
XMCP is an MCP (Model Context Protocol) server that connects Claude to a running Xojo IDE. Once connected, Claude can:  
- Inspect the project (get_project_info, list_project_items)  
- Read and write source code (get_code, set_code, and direct file editing)  
- Build, run, and stop the project (build_project, run_project, stop_project)  
- Search Xojo documentation (search_docs, lookup_class)  
- Read and write files on the Mac (xmcp:write_file, xmcp:read_file, xmcp:hash_file)  
XMCP does **not** launch the IDE or open projects — Xojo must already be running with the project loaded.  
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAAM0lEQVR4nO3OMQ0AIAwAwZIgBKm1gjSMNCwYYCIkd9OP3zJzRMQMAAB+sfqJeroBAMCN2pTWBSSZVtjzAAAAAElFTkSuQmCC)  
**2. Installing XMCP in Claude Desktop**  
**Step 1 — Build or locate the XMCP binary**  
Build the XMCP Xojo project for macOS ARM. The binary ends up at a path like:  
/Users/username/GitHub/XMCP-main/src/Builds - XMCP/macOS ARM 64 bit/XMCP/XMCP  
   
**Step 2 — Register it in Claude Desktop's config**  
The config file lives here:  
~/Library/Application Support/Claude/claude_desktop_config.json  
   
**Finding it on the Mac** — ~/Library is hidden by default, so use one of these routes:  
1. **Easiest — from inside Claude Desktop:** Claude Desktop menu →  **Settings → Developer → Edit Config**. This creates the file if it doesn't exist and reveals it in Finder.  
2. **Finder Go-to-Folder:** press  **Cmd+Shift+G**, paste ~/Library/Application Support/Claude/, press Return.  
3. **Finder Go menu:** click  **Go** in the menu bar while holding  **Option** — "Library" appears; then navigate to Application Support → Claude.  
4. **Terminal:**open ~/Library/Application\ Support/Claude/  
Open claude_desktop_config.json in a plain-text editor and add XMCP under mcpServers:  
{  
   "mcpServers": {  
     "xmcp": {  
       "command": "/Users/philipcumpston/GitHub/XMCP-main/src/Builds - XMCP/macOS ARM 64 bit/XMCP/XMCP"  
     }  
   }  
 }  
   
Optional launch arguments (from the XMCP README):  
{  
   "mcpServers": {  
     "xmcp": {  
       "command": "/path/to/XMCP",  
       "args": ["--docs-path", "/path/to/Documentation", "--verbose"]  
     }  
   }  
 }  
   
- --docs-path overrides documentation auto-detection (rarely needed).  
- -v/--verbose enables debug logging to stderr — useful when diagnosing connection problems via ~/Library/Logs/Claude/mcp*.log.  
Notes:  
- The binary path contains spaces — JSON handles this fine as long as it is one quoted string.  
- Startup order doesn't matter: XMCP can launch before the Xojo IDE. It retries the IDE socket (/tmp/XojoIDE, then /private/tmp/XojoIDE) on every request, so IDE tools simply start working once the IDE is open with a project loaded.  
**Step 3 — Restart Claude Desktop**  
Fully quit (Cmd+Q) and relaunch. XMCP should appear in the tools list (hammer/plug icon). If it doesn't:  
- Check the config file is valid JSON (a trailing comma is the usual culprit).  
- Check the binary has execute permission: chmod +x "<path to XMCP>".  
- Check Claude Desktop's MCP log: ~/Library/Logs/Claude/mcp*.log.  
**Step 4 — Smoke test**  
Open Xojo with a project loaded, then ask Claude:  
*"Call get_project_info and tell me what project is open."*  
If it returns the project name and directory, the connection works.  
**Step 5 — Install the local Xojo documentation (recommended)**  
The three documentation tools (search_docs, lookup_class, list_doc_topics) need the local docs:  
***Xojo IDE → Preferences → General → Install Local Documentation***  
XMCP auto-detects them on startup under ~/Library/Application Support/Xojo/Xojo/<version>/Documentation/. This is what lets Claude look up correct API 2 syntax instead of guessing from training data.  
**Step 6 — Semantic search (optional upgrade)**  
search_docs automatically switches from keyword search to **hybrid semantic search** when both of these are true at XMCP startup:  
1. xojo_rag.db (built with the XMCP-RAG indexer) sits in the same folder as llms-full.txt  
2. The local embedding server is running at http://localhost:8089/v1/embeddings (llama.cpp with nomic-embed-text)  
If either is missing, it falls back to keyword search transparently — nothing breaks, results are just less clever. Remember it is probed **once at startup**: start the embedding server before launching Claude Desktop.  
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OQQmAABRAsSd4EKxgBjP+Asa0hxW8ibAl2DIzR3UFAMBf3Gu1VefXEwAAXtsfSqwDVbgKngwAAAAASUVORK5CYII=)  
** **  
**3. Folder Structure for Skills**  
Skills are how Claude gets persistent, correct knowledge about your environment — Xojo API 2 rules, XMCP workflow, platform quirks. Set up the layout on the Mac as follows (Just create the folders):  
~/.claude/  
 ├── CLAUDE.md                          ← top-level instructions; points to the skills  
 └── skills/  
     └── user/  
         ├── xmcp/  
         │   ├── SKILL.md               ← XMCP workflow, tool usage, pitfalls  
         │   └── references/  
         │       ├── unhandled-exception.md  
         │       ├── window-escaping.md  
         │       └── xojo-file-formats.md  
         └── xojo-platform/  
             ├── SKILL.md               ← universal Xojo API 2 rules  
             └── references/  
                 ├── ios.md  
                 ├── android.md  
                 ├── desktop.md  
                 └── web.md  
   
**The three file types**  
**CLAUDE.md** — the entry point. Keep it short: identity/context, and explicit pointers to the skill files, e.g.:  
# Instructions  
 When working with Xojo, always read:  
 - ~/.claude/skills/user/xojo-platform/SKILL.md  
 - ~/.claude/skills/user/xmcp/SKILL.md (for any XMCP/IDE-control session)  
   
Security tip: only ever use a CLAUDE.md you wrote yourself. A shared or downloaded CLAUDE.md can contain prompt-injection instructions — review any third-party file line by line before adopting it.  
**SKILL.md** — one per skill, with YAML frontmatter followed by the content:  
---  
 name: xojo-platform  
 description: >  
   Use this skill whenever writing Xojo 2025 API 2 code for any target.  
   Trigger on any mention of Xojo, Xojo controls, or Xojo classes.  
 ---  
   
 # Skill content starts here...  
   
The description matters most — it is what triggers the skill. Write it as instructions ("Use this skill whenever…", "Trigger on any mention of…") and list the actual keywords that should fire it.  
**references/*.md** — detail files loaded on demand. Keep SKILL.md lean (workflow, rules, pitfalls) and push long material (platform-specific API notes, file-format specs, code templates) into references. This keeps context usage low until the detail is actually needed.  
**Maintaining skills**  
The single most valuable habit: **at the end of every session where a new bug, quirk, or workaround is discovered, ask Claude to add it to the relevant skill file.** Over time the skill becomes a distilled record of everything that ever went wrong, and Claude stops repeating old mistakes. A "Known Pitfalls" table works well for this.  
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OMQ2AUBBAsUeCE4yeIiT9CRVMWGAjJK2CbjNzVGcAAPzF2qu7Wl9PAAB47XoA/vcF8exqpY4AAAAASUVORK5CYII=)  
**4. The Standard XMCP Session Workflow**  
**At session start**  
1. Read the XMCP usage guide (an MCP resource: file://usage-guide.md) — it is authoritative and updated with the server. Tip: this file sits next to the XMCP binary and is read from disk at runtime, so you can edit it to add project-specific notes **without rebuilding XMCP**.  
2. get_project_info — confirms the IDE is running and returns the project directory (never guess paths).  
3. list_project_items — understand the structure before changing anything.  
4. Check App.xojo_code has an UnhandledException handler — without it, crashes in built apps are invisible.  
**Editing code — direct file editing is the primary method**  
get_code/set_code only work when a **method or property** is active in the IDE's code editor (selecting a class, module, or folder returns "No code editor is active"), and set_code does not save to disk — either the user presses Cmd+S or Claude calls save_project. Because of these constraints, the reliable pattern is to edit the source files on disk:  
1. **Read** the exact file content (xmcp:read_file, or grep/sed via DoShellCommand).  
2. **Check whitespace** — Xojo files mix tabs and spaces; use cat -v to see literal tabs before writing a match string. A missed tab causes a silent match failure.  
3. **Write a Python edit script** with xmcp:write_file to /tmp/script.py (this sidesteps all shell-quoting problems).  
4. **Verify syntax**: python3 -m py_compile /tmp/script.py.  
5. **Run it**: run_ide_script → DoShellCommand("python3 /tmp/script.py 2>&1").  
6. **Verify the change landed** (grep the file).  
7. **revert_project** so the IDE reloads the edited files — *always ask before this step; it discards unsaved IDE edits*.  
8. **analyze_project** or  **build_project** to check for errors.  
9. **Commit with git** via DoShellCommand.  
When creating a **new** .xojo_code file, register it in the .xojo_project file with a unique 16-digit hex ID:  
Class=MyClass;MyClass.xojo_code;&h1A2B3C4D5E6F7089;&h0000000000000000;false  
   
**Reading shell output back into Claude**  
Only the **function form** of DoShellCommand captures output in an IDE script:  
// CORRECT — returns stdout  
 Var output As String  
 output = DoShellCommand("cat '/path/to/file.xojo_code'")  
 Print output  
   
 // WRONG — output silently discarded  
 Call DoShellCommand "cat /tmp/file.txt"  
   
**Building and running**  
- DoCommand "BuildApp" (no arguments) uses the IDE's Build Settings. DoCommand "BuildApp 24 True" silently ignores the arguments — use BuildApp(24, True) (function form) for a specific target.  
- **build_project** ** can report success even when the build failed** in edge cases — always confirm visually that the app launched and behaved correctly.  
- In **debug mode**, runtime exceptions are caught by the IDE debugger and invisible to XMCP. In  **built apps** with an UnhandledException handler, use get_debug_log (and clear it after reading — it retains data from previous crashes).  
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OQQmAABRAsSd49m4tA8nPaQJjWMGbCFuCLTOzV2cAAPzFvVZbdXw9AQDgtesBorcEPwOKyvQAAAAASUVORK5CYII=)  
** **  
**5. Who Does What — Division of Labour**  
XMCP gives Claude a lot of reach, but some things remain physically or deliberately in the user's hands. This section can be pasted into CLAUDE.md or the xmcp skill as a standing instruction.  
**The user (Philip) does**  
| | |  
|-|-|  
| **Task** | **Why Claude can't** |   
| Open the Xojo IDE and load the project | XMCP connects to a running IDE; it cannot launch it or open projects |   
| Restart Claude Desktop after config/skill changes | MCP servers and config are read at app launch |   
| Install local Xojo documentation (IDE Preferences) | One-time manual IDE action |   
| Start the embedding server (if using semantic search) | Must be running before Claude Desktop launches |   
| Press **Cmd+S** after any set_code edit (or approve a save_project call) | set_code changes the editor buffer only |   
| **Approve ** **revert_project** before Claude calls it | It discards any unsaved IDE edits — only the user knows if there are any (Reloads memory from disk) |   
| **Visually confirm builds succeeded** and the app launches/behaves correctly | build_project can report success even when the build is unusable |   
| Report what the **IDE debugger** shows during debug runs | Runtime exceptions in debug mode are caught by the IDE and invisible to XMCP |   
| Approve destructive or irreversible steps (git resets, file deletions, project-file surgery) | Judgement call belongs to the owner |   
| Approve proposed additions to the skill files | Skills are the long-term memory; the user curates them |   
   
**Claude does (when asked)**  
| | |  
|-|-|  
| **Task** | **Tools used** |   
| Read the usage guide and orient in the project | MCP resources, get_project_info, list_project_items |   
| Read source files and check exact whitespace | xmcp:read_file, DoShellCommand (function form) with cat -v |   
| Write and deploy edit scripts | xmcp:write_file → /tmp/script.py → run_ide_script |   
| Verify edits landed | grep via DoShellCommand, xmcp:hash_file |   
| Create new project items / register new files | create_project_item, or direct .xojo_project edits |   
| Check the project compiles | analyze_project, build_project (then ask the user to confirm) |   
| Look up correct Xojo API 2 syntax | search_docs, lookup_class — instead of guessing |   
| Diagnose crashes in **built** apps | get_debug_log (with clear: true after reading), get_system_log |   
| Step through an active debug session | debug_control (step over/into/out, resume, pause) |   
| Commit work | git via DoShellCommand |   
| Propose skill updates when new quirks are discovered | End-of-session offer, user approves |   
   
**The two standing rules**  
1. **Claude asks before anything destructive** — revert_project, git operations that lose history, deleting files.  
2. **Claude never trusts "Build succeeded" alone** — the user is always asked to confirm the app actually launched and behaved correctly.  
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OMQ2AABAAsSPBCj7fFjsymJHAjAU2QtIq6DIzW7UHAMBfnGt1V8fXEwAAXrsexNkF4H1/HJoAAAAASUVORK5CYII=)  
**6. Known Pitfalls (Quick Reference)**  
| | |  
|-|-|  
| **Pitfall** | **Fix** |   
| DoCommand "Insert…" disconnects the IPC socket | Add controls by editing .xojo_window directly |   
| .xojo_window files not navigable via IDE scripting | Python file editing only |   
| revert_project discards unsaved IDE edits | Ask before calling |   
| list_doc_topics returns 143,000+ chars | Use search_docs or lookup_class |   
| Parallel XMCP tool calls fail | Always sequential |   
| IPC socket briefly drops after navigation | XMCP auto-retries (5 × 1 s); expect calls to take a few seconds longer, retry once more if needed |   
| get_code/set_code on a class or module | "No code editor is active" — navigate to a method/property, or edit the file directly |   
| select_project_item can't reach methods/events | Pass the full dot-path to get_code/set_code instead, or edit files directly |   
| set_code doesn't persist to disk | Cmd+S (user) or save_project |   
| Doc tools return nothing | Local documentation not installed — Xojo IDE → Preferences → General → Install Local Documentation |   
| Semantic search not activating | xojo_rag.db missing or embedding server not running *before* Claude Desktop launched |   
| Quotes in Python passed via echo | Write script with xmcp:write_file instead |   
| Base64 transfers | Never needed — use the native file tools |   
   
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OMQ2AABAAsSNhwgJGkPcrHpnRgQU2QtIq6DIze3UGAMBf3Gu1VcfXEwAAXrseaJkELjbMzy0AAAAASUVORK5CYII=)  
**7. Xojo API 2 Tips That Save the Most Time**  
These are the rules Claude most often gets wrong without a skill file:  
- Var, never Dim.  
- MessageBox takes one plain string, no inline calculations: compute first (Var n As Integer = i + 1), then concatenate n.ToString. MessageDialog for Yes/No dialogs.  
- Strings are never Nil — test with If s.Trim = "" Then.  
- In Catch e As RuntimeException, the message is e.Message.  
- One statement per line in Select Case — no colons.  
- One variable per Var line — no Var a, b As Integer.  
- Use Timer for timing, never Thread.Sleep in UI code.  
- #tag Constant with numeric Type and quoted Default silently evaluates to **0** — use local variables for numeric constants.  
- PDFDocument(width, height) needs Integer, not Double.  
- RegEx.Replace replaces only the **first** match unless Options.ReplaceAllMatches = True.  
- Xojo is case-insensitive — myVar and MyVar are the same identifier.  
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OMQ2AABAAsSPBCUZfE2IYmVDBhAU2QtIq6DIzW7UHAMBfnGt1V8fXEwAAXrse/xcF7U7sx4wAAAAASUVORK5CYII=)  
**8. Summary Checklist**  
**One-time setup**  
- Build XMCP; note the binary path  
- Add it to claude_desktop_config.json (Settings → Developer → Edit Config, or Cmd+Shift+G → ~/Library/Application Support/Claude/); restart Claude Desktop  
- Install local Xojo documentation (IDE → Preferences → General)  
- Optionally set up XMCP-RAG + embedding server for semantic doc search  
- Create ~/.claude/CLAUDE.md pointing to your skills  
- Create ~/.claude/skills/user/xmcp/SKILL.md and ~/.claude/skills/user/xojo-platform/SKILL.md with references/ subfolders  
**Every session**  
- Open Xojo with the project loaded, then start Claude  
- get_project_info → list_project_items  
- Edit via xmcp:write_file → /tmp/script.py → run_ide_script  
- Ask before revert_project; verify builds visually  
- Commit with git; add any new discovery to the skill file  
