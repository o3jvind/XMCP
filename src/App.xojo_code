#tag Class
Protected Class App
Inherits MCPKit.ServerApplication
	#tag Event
		Sub Configure()
		  // Set server identity.
		  Self.Name = "XMCP"
		  
		  // Connect to the Xojo IDE via IPC socket.
		  Try
		    IDE = New IDECommunicator
		    If Verbose Then System.DebugLog("IDE communicator initialized.")
		  Catch e As RuntimeException
		    System.DebugLog("WARNING: Could not connect to Xojo IDE: " + e.Message)
		    System.DebugLog("Make sure the Xojo IDE is running and the IPC socket is available at /tmp/XojoIDE or /private/tmp/XojoIDE.")
		    IDE = Nil
		  End Try
		  
		  // Detect documentation path.
		  Var docsPathStr As String = CommandLineParser.StringValue("docs-path")
		  If docsPathStr <> "" Then
		    // Use explicit --docs-path.
		    DocsPath = New FolderItem(docsPathStr, FolderItem.PathModes.Native)
		    If DocsPath = Nil Or Not DocsPath.Exists Then
		      System.DebugLog("WARNING: Specified docs path does not exist: " + docsPathStr)
		      DocsPath = Nil
		    End If
		  Else
		    // Auto-detect: scan ~/Library/Application Support/Xojo/Xojo/ for newest version.
		    DocsPath = DetectDocsPath
		  End If
		  
		  If DocsPath <> Nil Then
		    If Verbose Then System.DebugLog("Documentation path: " + DocsPath.NativePath)
		  Else
		    If Verbose Then System.DebugLog("WARNING: Xojo documentation not found. Doc tools will be unavailable.")
		  End If
		  
		  // Initialize semantic search if the RAG database and embedding server are available.
		  If DocsPath <> Nil Then
		    Var dbFile As FolderItem = DocsPath.Child("xojo_rag.db")
		    If dbFile <> Nil And dbFile.Exists Then
		      SemanticSearch = New SemanticSearch("http://localhost:8089/v1/embeddings", dbFile.NativePath)
		      If Verbose Then
		        If SemanticSearch.Available Then
		          System.DebugLog("Semantic search enabled.")
		        Else
		          System.DebugLog("Semantic search unavailable (embedding server not running or DB not ready).")
		          SemanticSearch = Nil
		        End If
		      ElseIf Not SemanticSearch.Available Then
		        SemanticSearch = Nil
		      End If
		    End If
		  End If
		  
		  // Configure the file tool sandbox (opt-in via --enable-file-tools).
		  Var fileToolsEnabled As Boolean = CommandLineParser.BooleanValue("enable-file-tools", False)
		  Var fileRoots As String = CommandLineParser.StringValue("file-root", "")
		  FileGuard.Configure(fileToolsEnabled, fileRoots)
		  If Verbose And fileToolsEnabled Then
		    Var rootsDesc As String = FileGuard.AllowedRootsDescription
		    System.DebugLog("File tools enabled. Allowed roots: " + rootsDesc)
		  End If
		  
		  // Register all MCP tools from the same list used by terminal help.
		  Var tools() As MCPKit.Tool = ConfiguredTools
		  For Each tool As MCPKit.Tool In tools
		    RegisterTools(tool)
		  Next tool
		  
		  If Verbose Then System.DebugLog("XMCP server configured with " + tools.Count.ToString + " tools.")
		  
		End Sub
	#tag EndEvent

	#tag Event
		Sub DidParseOptions()
		  If CommandLineParser.HelpRequested Then
		    CommandLineParser.ShowHelp("Options")
		    Print("")
		    Print("MCP Tools (" + ConfiguredTools.Count.ToString + "):")
		    Print("")
		    Print("  IDE Tools:")
		    Print("  list_project_items   List child items at a project location")
		    Print("  get_current_location Get the current Navigator location and type")
		    Print("  select_project_item  Navigate to a project item by path")
		    Print("  get_code             Read source code at current/specified location")
		    Print("  set_code             Write source code to current/specified location")
		    Print("  get_selected_text    Get selected text in the code editor")
		    Print("  set_selected_text    Replace selected text in the code editor")
		    Print("  build_project        Build the project (returns path or errors)")
		    Print("  run_project          Run the project in debug mode")
		    Print("  stop_project         Stop the running debug session")
		    Print("  create_project_item  Create a new class, method, property, etc.")
		    Print("  run_ide_script       Execute an arbitrary IDE script")
		    Print("  get_project_info     Get project path, Xojo version, and location")
		    Print("  revert_project       Reload project from disk after file changes")
		    Print("  get_item_description Get or set the description of a project item")
		    Print("  constant_value       Get or set the value of a project constant")
		    Print("  save_project         Save the project to disk")
		    Print("  analyze_project      Analyze project for errors and warnings")
		    Print("  debug_control        Step, resume, or pause an active debug session")
		    Print("  write_file           Write a file on disk (requires --enable-file-tools)")
		    Print("  read_file            Read a file from disk (requires --enable-file-tools)")
		    Print("  hash_file            Hash a file with MD5 or SHA256 (requires --enable-file-tools)")
		    Print("")
		    Print("  Documentation Tools:")
		    Print("  search_docs          Search Xojo documentation by keyword")
		    Print("  lookup_class         Look up detailed docs for a specific class")
		    Print("  list_doc_topics      List available documentation topics")
		    Print("")
		    Print("  Cost Awareness:")
		    Print("  estimate_request_cost Estimate likely token cost and alternatives")
		    Print("")
		    Print("  Debug Tools:")
		    Print("  get_debug_log        Read crash/exception log from /tmp/xmcp_debug.log")
		    Print("  get_system_log       Read System.DebugLog output from macOS unified log")
		    Print("")
		    Print("Usage:")
		    Print("  The XMCP server communicates via JSON-RPC over stdin/stdout (MCP protocol).")
		    Print("  It connects to the Xojo IDE via the IPC socket at /tmp/XojoIDE (or /private/tmp/XojoIDE).")
		    Print("  Documentation is auto-detected from ~/Library/Application Support/Xojo/")
		    Print("  or can be specified with --docs-path.")
		    Print("")
		    Print("  The write_file/read_file/hash_file tools are disabled by default. Enable")
		    Print("  them with --enable-file-tools and restrict access with --file-root, a")
		    Print("  comma-separated list of absolute paths (default: /tmp).")
		    Print("")
		    Print("  Make sure the Xojo IDE is running before starting this server.")
		    Print("")
		    Print("Example MCP client configuration (Claude Code):")
		    Print("  {")
		    Print("    ""mcpServers"": {")
		    Print("      ""xmcp"": {")
		    Print("        ""command"": ""/path/to/XMCP""")
		    Print("      }")
		    Print("    }")
		    Print("  }")
		    Quit
		  End If
		  
		End Sub
	#tag EndEvent

	#tag Event
		Sub WillParseOptions()
		  CommandLineParser.AppDescription = "MCP server for controlling the Xojo IDE"
		  CommandLineParser.AddOption("d", "docs-path", "Path to Xojo documentation directory (auto-detected if omitted)", MCPKit.OptionTypes.String)
		  CommandLineParser.AddOption("", "enable-file-tools", "Enable the write_file/read_file/hash_file tools (disabled by default)", MCPKit.OptionTypes.Boolean)
		  CommandLineParser.AddOption("", "file-root", "Comma-separated absolute paths the file tools may access (default: /tmp)", MCPKit.OptionTypes.String)
		  
		End Sub
	#tag EndEvent


	#tag Method, Flags = &h21
		Private Function CompareVersionNames(a As String, b As String) As Integer
		  Var aParts() As Integer = ExtractVersionParts(a)
		  Var bParts() As Integer = ExtractVersionParts(b)
		  
		  If aParts.Count > 0 Or bParts.Count > 0 Then
		    Var maxCount As Integer = Max(aParts.Count, bParts.Count)
		    For i As Integer = 0 To maxCount - 1
		      Var aValue As Integer = 0
		      Var bValue As Integer = 0
		      If i <= aParts.LastIndex Then aValue = aParts(i)
		      If i <= bParts.LastIndex Then bValue = bParts(i)
		      
		      If aValue > bValue Then Return 1
		      If aValue < bValue Then Return -1
		    Next i
		    Return 0
		  End If
		  
		  Var aNorm As String = a.Lowercase
		  Var bNorm As String = b.Lowercase
		  If aNorm > bNorm Then Return 1
		  If aNorm < bNorm Then Return -1
		  Return 0
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ConfiguredTools() As MCPKit.Tool()
		  /// Returns the complete tool list exposed by XMCP.
		  /// Keep this as the single source of truth for startup registration and
		  /// terminal help counts so documentation cannot drift from reality.
		  
		  Var tools() As MCPKit.Tool
		  tools.Add(New ListProjectItems)
		  tools.Add(New GetCurrentLocation)
		  tools.Add(New SelectProjectItem)
		  tools.Add(New GetCode)
		  tools.Add(New SetCode)
		  tools.Add(New GetSelectedText)
		  tools.Add(New SetSelectedText)
		  tools.Add(New BuildProject)
		  tools.Add(New RunProject)
		  tools.Add(New StopProject)
		  tools.Add(New CreateProjectItem)
		  tools.Add(New RunIDEScript)
		  tools.Add(New GetProjectInfo)
		  tools.Add(New GetItemDescription)
		  tools.Add(New ConstantValue)
		  tools.Add(New SearchDocs)
		  tools.Add(New LookupClass)
		  tools.Add(New ListDocTopics)
		  tools.Add(New RevertProject)
		  tools.Add(New EstimateRequestCost)
		  tools.Add(New GetDebugLog)
		  tools.Add(New GetSystemLog)
		  tools.Add(New SaveProject)
		  tools.Add(New AnalyzeProject)
		  tools.Add(New DebugControl)
		  // File tools are opt-in: direct filesystem access is a larger attack
		  // surface than the IDE-mediated tools, so it requires an explicit flag.
		  Var enableFileTools As Boolean = CommandLineParser.BooleanValue("enable-file-tools", False)
		  If enableFileTools Then
		    tools.Add(New WriteFile)
		    tools.Add(New ReadFile)
		    tools.Add(New HashFile)
		  End If
		  
		  Return tools
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function DetectDocsPath() As FolderItem
		  // Look for Xojo docs at ~/Library/Application Support/Xojo/Xojo/<version>/Documentation/
		  Var appSupport As FolderItem = SpecialFolder.ApplicationData
		  If appSupport = Nil Then Return Nil
		  
		  Var xojoDir As FolderItem = appSupport.Child("Xojo").Child("Xojo")
		  If xojoDir = Nil Or Not xojoDir.Exists Then Return Nil
		  
		  // Find the newest version directory that has Documentation/llms-full.txt.
		  Var bestDir As FolderItem = Nil
		  Var bestName As String = ""
		  
		  For i As Integer = 0 To xojoDir.Count - 1
		    Var item As FolderItem = xojoDir.ChildAt(i)
		    If item = Nil Or Not item.IsFolder Then Continue
		    
		    Var docsDir As FolderItem = item.Child("Documentation")
		    If docsDir = Nil Or Not docsDir.Exists Then Continue
		    
		    Var llmsFile As FolderItem = docsDir.Child("llms-full.txt")
		    If llmsFile = Nil Or Not llmsFile.Exists Then Continue
		    
		    // Pick the highest semantic version directory (e.g. 2024r10 > 2024r9).
		    If bestDir = Nil Or CompareVersionNames(item.Name, bestName) > 0 Then
		      bestName = item.Name
		      bestDir = docsDir
		    End If
		  Next i
		  
		  Return bestDir
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ExtractVersionParts(value As String) As Integer()
		  Var parts() As Integer
		  Var currentDigits As String = ""
		  
		  For i As Integer = 0 To value.Length - 1
		    Var ch As String = value.Middle(i, 1)
		    If ch >= "0" And ch <= "9" Then
		      currentDigits = currentDigits + ch
		    ElseIf currentDigits <> "" Then
		      parts.Add(currentDigits.ToInteger)
		      currentDigits = ""
		    End If
		  Next i
		  
		  If currentDigits <> "" Then
		    parts.Add(currentDigits.ToInteger)
		  End If
		  
		  Return parts
		  
		End Function
	#tag EndMethod


	#tag Note, Name = refactoring
		Starting XMCP with the flags
		The two new options work together: --enable-file-tools switches the three file tools on (without it, XMCP starts with 25 tools and no filesystem access at all), and --file-root takes a comma-separated list of absolute directories the tools may touch. If you enable the tools but omit --file-root, the sandbox defaults to /tmp alone — enough for script deployment but nothing else.
		For Claude Desktop, this lives in the args array of the config, which I've already set up for you:
		json"xmcp": {
		  "command": "/Users/philipcumpston/GitHub/XMCP/src/Builds - XMCP/macOS ARM 64 bit/XMCP/XMCP",
		  "args": [
		    "--docs-path", "/Users/philipcumpston/Library/Application Support/Xojo/Xojo/Xojo 2026r1.2/Documentation",
		    "--enable-file-tools",
		    "--file-root", "/tmp,/Users/philipcumpston/GitHub"
		  ]
		}
		Note that --file-root and its value are separate array elements, and the comma-separated list is one string with no spaces around the commas. You never launch XMCP yourself in normal use — Claude Desktop starts it when the app launches, so the flags take effect at your next restart of Claude Desktop.
		For testing in Terminal, you can launch the binary directly. --help shows the options and the annotated tool list, and a manual run with flags looks like:
		bash"/Users/philipcumpston/GitHub/XMCP/src/Builds - XMCP/macOS ARM 64 bit/XMCP/XMCP" \
		  --enable-file-tools --file-root "/tmp,/Users/philipcumpston/GitHub"
		It will sit waiting for JSON-RPC on stdin (Ctrl-C to quit) — that's exactly how my test harness drove it. Adding -v turns on verbose logging, which now includes a startup line confirming the resolved roots: File tools enabled. Allowed roots: /private/tmp, /Users/philipcumpston/GitHub (the /private prefix is the canonicalised form of /tmp and is expected).
		For Claude Code, if you ever use XMCP there, the equivalent is claude mcp add xmcp -- "/path/to/XMCP" --enable-file-tools --file-root "/tmp,/Users/philipcumpston/GitHub" — though for that audience you'd typically omit both flags, since Claude Code has its own file tools, which is precisely the default-off behaviour the maintainer wanted.
		
		
	#tag EndNote


	#tag Property, Flags = &h0, Description = 5061746820746F20586F6A6F20646F63756D656E746174696F6E206469726563746F72792E
		DocsPath As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h0, Description = 546865207368617265642049444520636F6D6D756E696361746F7220696E7374616E63652E
		IDE As IDECommunicator
	#tag EndProperty

	#tag Property, Flags = &h0
		SemanticSearch As SemanticSearch
	#tag EndProperty


	#tag ViewBehavior
		#tag ViewProperty
			Name="Name"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="String"
			EditorType="MultiLineEditor"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Verbose"
			Visible=false
			Group="Behavior"
			InitialValue="False"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
