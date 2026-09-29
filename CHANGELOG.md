# Changelog

All notable changes to XMCP will be documented here.

## [Unreleased]

### Fixed
- **Split replies are merged instead of raced.** One request can be answered by several messages under the same tag: a script's `Print` output and a compiler warning about that script arrive about a millisecond apart, and an analysis answers with its `buildError` and the `Print` sentinel together. Returning on the first matching frame made the answer whichever part won the race, so a successful script sometimes reported only a warning and an analysis sometimes reported nothing. `IDECommunicator` now keeps reading until the answer is complete (see the end-marker entry below) and folds the parts into one envelope: an error part is the answer, otherwise the output is, and a warning is the answer only when it is all there is.
- **A timed-out socket is parked, not closed.** The IDE runs scripts one at a time on its main thread, so during a build it answers nothing until it is done, then answers everything that queued up, on the connections the requests arrived on. Closing such a socket meant the IDE's later write hit a closed peer and raised `SIGPIPE`, which the Xojo IDE does not ignore — it died mid-build with no crash report (`exited due to SIGPIPE | sent by Xojo`, five seconds after the build finished). The socket is now kept open until the IDE has finished answering (see the end-marker entries below), or has closed it, or it can no longer be read from, or two hours have passed - the one limit past which a late answer would still hit a closed peer. While one is parked, further requests are refused rather than queued behind a busy IDE, and the refusal names the script still outstanding. The guarantee that a delivered script is never retried is preserved — it now comes from the parked state rather than a `scriptWasSent` flag.
- **No request can hang on a script that prints nothing.** Measured against the IDE socket directly: the IDE answers once per `Print`, twice for two `Print`s, and **not at all** for a script with no `Print`. Such a request timed out, parked its socket, and left every later request refused until the give-up timer expired — one `Print`-less script blocked the session. A `Print` is now appended in `SendAndReceive`, the single point every tool passes through, so a tool cannot forget it and a caller-supplied script cannot reintroduce the failure. It is skipped when the script ends in a line continuation, where appending would be absorbed into that line and change its meaning. Since real output outranks an empty reply, a script that does print still reports its own output.
- **One classifier for every reply shape.** `ReplyKind`, `ReplyDiagnostics` and `ReplyWarnings` in `IDECommunicator` are now the single place that decides what a reply is and how it reads. `run_ide_script`, `build_project` and `run_project` previously each judged it differently: `run_ide_script` handed the caller a raw JSON dump (`"Script error: " + the whole envelope`), and `build_project`/`run_project` parsed only `buildError.errors`, so `missingFiles`, `openErrors` and `loadError` fell through to a raw dump under `"Build failed:"`. All four shapes now render the same way in every tool, script error line numbers are corrected for the boilerplate line the IDE wraps each script in, and warnings without errors report as success with the warnings attached.
- **A non-object reply part no longer fails the request.** A two-`Print` script returned the JSON-RPC parse error `Item is an array`: the merged envelope attaches the other parts' response *values*, which for a multi-`Print` script are plain strings, and reading warnings out of one raised an exception that escaped the tool. Reading warnings out of a reply can no longer fail the reply.

- **A parked socket is released while idle, not only on the next request.** The IDE serves one IPC connection at a time, so a parked socket holds the slot against every other client - another XMCP, or the IDE Communicator example. Draining only when the next request arrived meant an XMCP that parked a socket and then went quiet locked the IDE away from everyone until the give-up timer expired. `ServerApplication` now raises an `Idle` event on every pass of its stdin loop, and `App` drains there, so the socket is released as soon as the IDE answers.
- **Build and run waits are configurable, and generous by default.** `build_project` and `run_project` took a hardcoded wait that a real build outlives, so a build that succeeded was reported as a timeout. Both now take an optional `timeout`, defaulting to 30 minutes. Verified against builds that exceed the old cap on both platforms: 335 s on macOS, 169 s on Windows, each returning a real result rather than a timeout.
- **A script's warnings are reported even when it printed nothing.** `run_ide_script` computed the warning text and then dropped it on both no-output returns, so a compiler warning was heard only when the script happened to print something as well: `Var i As Integer = 3.7` followed by a `Print` reported the narrowing-precision warning, while the same statement alone reported "produced no value" and nothing else. The no-output reply now carries the warnings too.
- **The other thirteen tools report through the classifier too.** `RunScript` - the path `set_code`, `constant_value`, `get_code`, `select_project_item` and nine others take - kept its own rules. Any reply carrying `scriptError` became a Failure with the envelope dumped as raw JSON, so a script that merely raised a compiler warning was reported as an outright failure; and a warning arriving with real output was dropped, because the merged parts were never read. `get_selected_text` lost one on every call. It now uses the shared classifier. Warnings from these tools' own generated scripts are kept out of the data they return and reported only when the script printed nothing, since for most of them the result is data and a diagnostic appended to it would corrupt it.
- **`analyze_project` reads every kind of IDE reply, and its wait can be changed.** It understood only build errors; any other kind of reply - a missing file, a project that failed to open or load - came back as raw JSON under "Unexpected response". It now uses the shared classifier, while keeping its own "Analysis results" heading, since it does not build. Its fixed 60-second wait, too short for a large project, is now a `timeout` parameter defaulting to five minutes.
- **A `timeout` of zero no longer leaves `run_ide_script` waiting.** Four tools take a `timeout` argument and `run_ide_script` was the only one that did not check it, so `timeout: 0` meant "wait no time at all": the request gave up at once, and every later request was turned down until the IDE answered one nobody was waiting for. All four now read the argument the same way, and a zero or negative value means "use the default".
- **`get_project_info` no longer reports a script error as success.** It read the reply itself and stringified a non-string response into the result, so a `scriptError` came back as a raw JSON dump wrapped in Success. It now goes through `RunScript`.
- **`revert_project` no longer keeps its own error classifier.** A private `ScriptErrorText` treated any non-string reply as an error, including a warnings-only reply and the empty object the IDE sends for `Print ""`. It uses `ReplyDiagnostics`.
- **Output beginning "Error:" is no longer mistaken for a failure.** `RunScript`'s test for a tool's own `ERROR:` guard used `BeginsWith`, which is case-insensitive by default in this Xojo version, so a constant's value or a line of selected code beginning "Error:" was reported as one. The test is now case-sensitive and untrimmed; every tool that prints a guard prints `ERROR:` in capitals at the very start.
- **A whitespace-only script no longer parks.** `run_ide_script` compared against exact `""` and let it through, and the sentinel was skipped for it, so it reached the IDE with no `Print`. The tool now trims, and the transport appends the sentinel to an empty or whitespace-only script as well.
- **A script ending in a comment or a name that ends in `_` no longer parks.** The sentinel was skipped whenever the script's last character was an underscore, treating it as a line continuation. Measured: a comment can end in one without continuing, and `foo_` is a legal name. The test now removes a trailing comment first and counts an underscore only when it does not end a name, appending the sentinel whenever it is unsure.
- **No path that may have delivered a request closes or resends it.** A frame for another tag used to close the socket and return without parking - resending a script the IDE had accepted, and closing a connection it still owed a reply on. An unguarded `Poll`/`ReadAll` could throw past both the merge and the parking. A write that failed partway closed the socket and let the next candidate path resend, and on macOS that path is usually the same socket (`/tmp` is `/private/tmp`). The frame parser caught only `JSONException`, so any other exception escaped the same way. All of these now park. The `Poll` that waits for the connection, before anything is sent, was unguarded too; an exception there escaped as an unexplained error rather than a failed connect. It is now reported as a failed connect, the same as a failing `Connect`. Nothing had been sent, so nothing needs to park.
- **Most IDE calls are about 200 ms faster.** After the first part of an answer, XMCP used to keep reading for a fixed 250 ms in case more parts came, so nearly every call paid that wait in full. The `Print` XMCP appends to every script now prints a marker unique to the request, which XMCP never passes on; when it arrives the script has finished, and only the compiler warning the IDE sends just after the last `Print` can still come - measured at under a millisecond on macOS and Windows. XMCP now waits 50 ms after the marker instead. A typical call went from about 500 ms to about 300 ms. Replies that stop before the marker - compile errors, runtime errors, a script ending in a line continuation - keep the 250 ms wait.
- **A runtime error now says what it is.** The IDE reports a runtime error in a script with an empty message and line 0, so it came back as `scriptRuntimeError:` followed by nothing. XMCP now says the script stopped with a runtime error that the IDE gave no details for, and names the usual causes.
- **`revert_project` no longer reports a step as failed while the IDE is still doing it.** Several steps send a request, ignore its reply and check the effect with a second call. If the first request was still being carried out - a slow close, a dialog - the second call was turned down, and the tool said the IDE "stopped responding" or the project "did not reopen". It now says the IDE has not finished that step yet, and what to check once it has. On Windows the same applies to closing the temporary empty project the tool opens so that closing yours cannot quit the IDE: that close is the tool's last request, so a stall there used to go unmentioned - a plain success, while further requests were being turned down.
- **A waiting request's connection is closed only after the IDE has finished answering.** It used to be released as soon as the first byte of the answer arrived, which on Windows - where a large answer arrives in pieces - could close it while the IDE was still writing, and on macOS and Linux that can crash the IDE. It was then released on the first complete part of the answer, which still cut off an answer made of several parts. It is now released once its answer is complete - its end marker, or an error that stopped the script - and nothing more has arrived for 250 ms. A pause, or a part meant for another request, no longer counts as the end.
- **An answer is complete when the script has finished, not when it goes quiet.** The IDE sends each `Print` the moment it runs, so a script that prints, then works or waits on a build or a dialog, then prints again, goes quiet in between (measured: two `Print`s 232 ms apart around 232 ms of work). XMCP used to return and close the connection 250 ms after the first part of an answer, and to release a waiting request after any part followed by 250 ms of quiet - even a part meant for another request. Both could close the connection while the script was still running, so the IDE's next `Print` went into a closed connection, which on macOS and Linux crashes the IDE. Both now use one rule: the answer is complete when its end marker arrives, or when a compile or runtime error stops the script - or, for a script that ends in a line continuation and so gets no marker, on its first part that is not warnings alone. Output that arrives without either, within the time limit, means the script is still running, and the request is parked. The 50 ms wait after the marker is no longer cut short by the time limit. A request that parks in the middle of a part keeps what had already arrived of it, so it can still recognise its own end - otherwise a time limit falling inside the end marker would have left it waiting, and every other request turned down, for two hours.
- **Tags are unique per XMCP process.** Every XMCP process numbered its request tags from `xmcp_1`. An answer the IDE owes on a connection that has gone away - its XMCP was killed or restarted while a request was waiting - is handed to the next client that connects, ahead of that client's own answer and with its original tag (measured on Windows, where the IDE survives that). So a new XMCP's first request could carry the same tag and take the other's late answer, end marker included, for its own. Reproduced on Windows: a second XMCP asked for `Print "B-own-answer"` and got the first one's `A-late-answer`, reported as success. Tags now carry a random part chosen once per process (`xmcp_3f9a1c2e_1`); with them the same test returns `B-own-answer`. The verbose log now names the tag of a frame it ignores.
- **Opening a project saved by an older Xojo is no longer reported as a failure.** The IDE answers `{"openErrors":[{"loadError":{"type":"IDE Version Conflict", ..., "severity":"warning"}}]}` and opens the project, but every `openErrors` result was classified as an error, so the call failed. A result of exactly that measured shape - entries holding only objects, each saying severity "warning" and holding only plain values - is now a warning: `run_ide_script` succeeds and shows it, for example "Warning while opening the project: IDE Version Conflict (projectVersion 2026.011, ideVersion 2026.021)". Anything else in `openErrors` is still an error. `revert_project`, which checks a reopen by the project's path rather than by the reply, does not repeat the warning. `run_ide_script` now introduces warnings as "The IDE also reported warnings (the script still ran)", since not every warning is about the script.
- **XMCP stops waiting as soon as the IDE closes the connection.** It used to wait out the whole time limit - up to 30 minutes for a build - and then report that the IDE was busy and must not be interrupted, when the IDE had in fact quit or crashed. It now says the IDE closed the connection, and still does not send the request again, since the IDE may have run it.
- **A reply in a shape the IDE has never sent can no longer escape between sending a request and parking it.** `ReplyKind` converted parts of the reply to objects without a guard; one that was not an object would have thrown after the request was sent, so the request would have been neither answered nor parked. It now counts as an error, and is reported - and `ReplyDiagnostics`, which reads the details, reports such a reply as it arrived instead of throwing while reading it.
- **`build_project`, `run_project` and `analyze_project` judge a result the same way.** A build result whose error and warning lists are both empty was reported as "Build failed: {...}" by the first two, while the shared classifier and `analyze_project` called it clean. All three now ask the classifier whether there is anything to report, convert the reply safely when it is neither text nor an object, and - `analyze_project` included - report a build result they cannot read as it arrived instead of throwing.
- **A build result in a shape the IDE has never sent is no longer taken for success.** Only its two lists were read, so `{"buildError":{}}` or a build result carrying anything else counted as a clean build, and the first error key found decided the whole reply. Every error key is now looked at, and a build result counts as clean only in the shape the IDE sends (measured: an `errors` list, a `warnings` list, or both); anything else is reported as an error, shown as it arrived. `analyze_project` uses the same test before formatting a result its own way.
- **The wait after an answer has ended is never cut short.** The 250 ms after an error that stopped the script could be cut off by the time limit, while the 50 ms after the end marker could not; now neither is. And if that wait runs out while a part is still half read, XMCP reads on until the part is whole - at most one second - instead of closing while the IDE is still writing it.
- **`revert_project` on Windows keeps track of the empty project it opens.** It opens one so that closing your project cannot quit the IDE, and closes it before returning. Where the tool stopped early, or the close stalled, failed, or could not be checked, the empty project could be left open with nothing saying so, and one note named the wrong step. Every such result now says the empty project may still be open - and to close it only once your own project is open again, because on Windows closing the last open project quits the IDE.
- **`revert_project` on macOS gives the right reason when the reopen fails.** It read the error after the next request had already replaced it, so the reason was usually missing.
- **`revert_project` says why it could not read the window count.** The cause - usually a parked-request refusal - was discarded in favour of a generic "might quit the IDE" message.

### Changed
- **You are now warned not to quit Claude Code while the IDE is still answering a request.** When a request takes longer than its time limit, XMCP keeps its connection to the IDE open until the answer arrives. Quitting or restarting Claude Code in that window stops XMCP, which closes the connection, and on macOS and Linux the Xojo IDE crashes when it then answers. The messages XMCP returns while a request is waiting now say so, so the AI in the session can pass it on. XMCP cannot prevent it itself yet: Claude Code stops XMCP with a signal, and XMCP stops at once when it gets one. An attempt to make XMCP wait at shutdown was taken out again, because testing showed the moment it relied on is never reached - XMCP does not notice when a program simply stops talking to it. Both are written up in the README under "Decisions and known limits", with a possible fix (A′) left for later.


## [1.11.0] - 2026-09-17

### Added
- **`write_file`, `read_file`, `hash_file`**: opt-in direct filesystem access for MCP clients with no file tools of their own (e.g. Claude Desktop), disabled by default and registered only with `--enable-file-tools`. Access is restricted to an allowlist of directories given via `--file-root` (comma-separated absolute paths, default `/tmp`), enforced by a new `FileGuard` module: paths are lexically canonicalised, then resolved through `realpath(3)` before comparison so a symlink inside an allowed root can't be used to escape it (residual risk: the check and the file open are separate syscalls, so a symlink swapped in between would still escape — recorded in `FileGuard`'s design notes). `write_file` accepts an optional `expected_hash` (from `hash_file`) and refuses the write if the file changed since it was hashed, so a concurrent edit is never silently discarded. `read_file` chunks by character offset (never splits a multibyte UTF-8 sequence) and returns content verbatim with no added header, so a round-trip `read_file` → `write_file` never corrupts the file. `hash_file` streams MD5/SHA-256 in 1 MB chunks via a shared `FileDigest` module, so file size isn't limited by available memory, and both tools compute digests through the same code so a staleness guard can never disagree with the hash a caller obtained.
- **`ConfiguredTools()`**: `App` now builds its tool list once and reuses it for both startup registration and the `--help` tool count/list, so the two can no longer drift apart.
- **Credit**: original design and implementation by [@supcumps](https://github.com/supcumps) (Philip Cumpston) in #2, including the sandboxing model, the opt-in flag, and the symlink/staleness hardening added during review. The port onto `main` (#7) credited him only in prose, without the `Co-authored-by:` trailer GitHub's contributor graph looks for — this entry's commit adds it.

## [1.10.1] - 2026-09-08

### Fixed
- **`OptionParser.ArrayValue`**: no longer throws `TypeMismatchException` when an array-type option (e.g. `--docset-path`) was never supplied on the command line. The unset option's `Value` holds a scalar empty-string `Variant`, and assigning it directly into a `Variant()` array crashed the whole server at startup — including in MCP clients like Claude Desktop, whose config invokes XMCP with no arguments at all. Fixed by checking `o.WasSet` before reading `o.Value`, so an unset array option now correctly yields an empty array.

## [1.10.0] - 2026-09-07

### Added
- **`list_docsets`, `search_docset`, `get_docset_entry`**: search third-party documentation from Dash/Zeal-style `.docset` bundles, registered via one or more `--docset-path` flags. `list_docsets` lists registered bundles with entry counts; `search_docset` searches entry names across all or one docset (`docset_name` parameter); `get_docset_entry` reads a specific entry's HTML content, stripped to plain text. Independent of `search_docs`/`lookup_class`, which remain Xojo-specific.
- New `Docset.xojo_code` class wraps a single `.docset` bundle's SQLite `searchIndex` table and HTML `Documents/` tree, following the same lazy-probe pattern as `SemanticSearch` so an unreadable bundle degrades gracefully instead of failing startup.
- **Tarix-packed docsets**: some Dash distributions (e.g. AppleScript) ship no `Documents/` folder at all, only a `Contents/Resources/tarix.tgz` archive. `Docset` now shells out to the system `tar` to extract such an archive once into `~/Library/Application Support/dk.o3jvind.xmcp/docset-cache/<name>/` on first `get_docset_entry` call, then reads from the cache thereafter. Xojo's built-in `FolderItem.Unzip`/`.Zip` only cover the ZIP format, not tar+gzip, so this is the only dependency-free option (the alternative, MBS's Compression/Archive plugin, would add a new project-wide dependency).

## [1.9.1] - 2026-09-06

### Fixed
- **`IDECommunicator.RunScript`**: stopped re-parsing string tool output as JSON to look for `scriptError`/`buildError` keys. No `RunScript` caller ever emits that shape (only `DoCommand "RunApp"`/`"BuildApp"` do, and they bypass `RunScript` and call `SendAndReceive` directly) — the check only ever misclassified legitimate text as a failure, e.g. a constant value or item description whose content happened to contain the literal text `{"buildError":...}`. Also normalizes an empty-object IDE response (`{}`) back to `""`.
- **`Tool.BuildStringVariableScript`** (shared by `constant_value`, `get_item_description`, `set_code`, `set_selected_text`): rebuilt to split on CRLF/CR/LF individually and join segments with explicit `Chr(13)`/`Chr(10)` separators, instead of splitting only on `EndOfLine` (LF-only on macOS) and appending `+ EndOfLine` after every element. This fixed three related bugs: a value already ending in a line break got an extra blank line appended on write; a lone CR left a raw control byte inside a generated script's string literal, which could break the script's syntax; and `constant_value`'s read-back verification compared against the same corrupted value it had just written, so neither bug was ever caught by the "did the write take effect" check.
- **`scaffold_code_block`**: `EscapeConstantDefault` now normalizes CRLF and lone CR to LF before escaping a constant `Default` value. Previously a lone CR was silently deleted by the `constant_escape` table's `"\r" -> ""` entry (corrupting the value), and any line break split the generated `#tag Constant` line, producing an invalid definition. `usage-guide.md`'s `constant_escape` table now also maps `\n` to the `.xojo_window`-style `\n` escape.
- **`ServerApplication`**: `RequestID` is now reset to `Nil` before parsing each stdin line, so a JSON parse failure correctly reports `id: null` per the JSON-RPC spec instead of reusing the previous successful request's id.

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
