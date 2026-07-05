**File tools: opt-in registration, sandboxed roots, and the two bug fixes**  
This follow-up implements the changes we discussed. The short version: the three file tools are now **disabled by default**, sandboxed to an  **explicit directory allowlist** when enabled, and both technical issues you identified (whole-file hashing, byte-vs-character offsets) are fixed. A default launch of XMCP is byte-for-byte equivalent in behaviour to a build without the file tools at all — 25 tools registered, zero filesystem surface.  
**Why keep them in XMCP at all**  
My target client is Claude Desktop, which — unlike Claude Code — has no built-in file tools on the Mac side. A standalone filesystem MCP server is technically an option, but it means a second server to install and configure, and most grant equally broad access unless carefully scoped. More importantly, the workflow is coupled to XMCP: the primary editing pattern is *write a Python edit script to /tmp with * *write_file* *, execute it via * *run_ide_script → DoShellCommand* *, verify with * *hash_file*. These tools exist to support IDE-adjacent editing, not general file I/O — and the changes below now make that boundary explicit in code rather than just in intent.  
**1. Opt-in registration (**--enable-file-tools **)**  
The tools are only constructed and registered when the server is started with --enable-file-tools. ConfiguredTools() remains the single source of truth: the gate lives inside it, so startup registration, the MCP tools/list response, and the --help count can never disagree. Without the flag, --help reports 25 tools and the three file-tool entries are annotated "(requires --enable-file-tools)". Claude Code users who never pass the flag see no change and no duplication of their built-in tools.  
**2. Sandboxed roots (**--file-root **, new **FileGuard ** module)**  
When enabled, access is restricted to a comma-separated allowlist of absolute paths, defaulting to /tmp if the option is omitted. A new FileGuard module holds the policy: Configure() is called once from App.Configure, and all three tools call FileGuard.Validate(path, ByRef reason) before touching disk. Validation applies to **reads as well as writes** — unrestricted reads are an exfiltration surface (~/.ssh, keychains, browser profiles), so the sandbox is uniform.  
Paths are lexically canonicalised before comparison: . and .. segments resolved (with .. above root clamped at root), duplicate slashes collapsed, relative paths rejected outright, and the standard macOS symlinked prefixes /tmp, /var and /etc mapped to their /private equivalents so that /tmp/x and /private/tmp/x compare identically. Prefix matching appends a trailing separator so /tmp cannot accidentally admit /tmpfoo.  
**Known limitation, documented in the code and usage guide:** canonicalisation is lexical only. A symlink *inside* an allowed root can still point outside it. Resolving that properly needs realpath(3) declares (macOS-specific) or per-component stat walking; I judged that out of scope for v1 but am happy to add it if you'd like it as a merge condition.  
**3. **hash_file ** now streams (your first catch)**  
The whole-file MemoryBlock read is gone — the stale #tag Note in App.xojo_code that promised streaming has been removed along with it. Files are now processed in 1 MB chunks:  
- **MD5** uses Xojo's incremental MD5Digest class (Process() per chunk).  
- **SHA-256** has no incremental equivalent in Xojo (Crypto.SHA2_256 is one-shot only), so on macOS it streams through CommonCrypto via declares (CC_SHA256_Init/Update/Final from libSystem). On other targets it falls back to the previous whole-file behaviour, with a comment noting this is pending an incremental SHA-2 API in Xojo.  
**4. **read_file ** offsets are now true character offsets (your second catch)**  
The implementation previously seeked byte positions on a BinaryStream while the parameter docs promised characters — wrong results on multibyte UTF-8, exactly as you said. It now decodes the file as UTF-8 first and slices with String.Middle, so offset/length behave precisely as documented and can never split a multibyte sequence. The summary header reports character counts accordingly. (Trade-off: the file is fully read before slicing, so chunking limits *response* size rather than memory — appropriate for the text files this tool targets.)  
**5. Documentation**  
usage-guide.md gains an "Optional file tools (opt-in)" section covering the flags, the character-offset semantics, streaming behaviour, the symlink limitation, and an example Claude Desktop args configuration. The --help usage text explains the same in brief.  
**Testing**  
Beyond analyze_project (clean) and a successful build, I drove the built binary directly over JSON-RPC with a Python harness, using hashlib and Python's own character slicing as ground truth:  
| | |  
|-|-|  
| **Check** | **Result** |   
| MD5 digest matches hashlib.md5 | pass |   
| SHA-256 digest matches hashlib.sha256 (CommonCrypto path) | pass |   
| Multi-chunk hashing: 5.5 MB random file (6 chunks, partial final chunk), both algorithms | pass |   
| read_file offset=6 length=10 on multibyte UTF-8 matches Python content[6:16] | pass |   
| Read outside allowed root → "Access denied" | pass |   
| /tmp/../etc/… dot-segment escape → "Access denied" | pass |   
| Write inside root succeeds; content verified on disk | pass |   
| Default launch (no flag): tools/list returns 25 tools, no file tools | pass |   
| Custom --file-root list admits the additional root | pass |   
   
**Files changed**  
- src/FileGuard.xojo_code — **new** module: policy, canonicalisation, validation  
- src/App.xojo_code — two new options, FileGuard.Configure at startup, gated registration in ConfiguredTools(), help text updates, stale note removed  
- src/Tools/WriteFile.xojo_code — FileGuard.Validate before writing; description updated  
- src/Tools/ReadFile.xojo_code — character-offset implementation; FileGuard.Validate; description updated  
- src/Tools/HashFile.xojo_code — chunked streaming for both algorithms; FileGuard.Validate; description updated  
- src/XMCP.xojo_project — FileGuard registration  
- src/usage-guide.md — file tools section  
Happy to adjust any of the defaults (root list, chunk size, flag names) or add realpath-based symlink resolution if you'd prefer that before merging. Thanks again for the careful review — both bugs were real, and the opt-in shape is a better design than what I originally submitted.  
