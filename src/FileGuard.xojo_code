#tag Module
Protected Module FileGuard
	#tag Method, Flags = &h0
		Sub Configure(enabled As Boolean, rootsCSV As String)
		  // Called once at startup from App.Configure.
		  // Parses the --file-root option (comma-separated absolute paths) into
		  // a canonicalised allowlist. If enabled with no roots given, defaults
		  // to /tmp so script deployment works out of the box.
		  
		  mEnabled = enabled
		  mRoots.RemoveAll
		  
		  If Not enabled Then Return
		  
		  Var cleaned As String = rootsCSV.Trim
		  If cleaned = "" Then
		    cleaned = "/tmp"
		  End If
		  
		  Var parts() As String = cleaned.Split(",")
		  For Each p As String In parts
		    Var candidate As String = p.Trim
		    Var norm As String = NormalizePath(candidate)
		    If norm <> "" Then
		      // Resolve the root itself: a root that is a symlink would otherwise
		      // never match the resolved paths it is compared against.
		      mRoots.Add(NormalizePath(ResolvedOrLexical(norm)))
		    End If
		  Next p
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Enabled() As Boolean
		  // True when the file tools were enabled via --enable-file-tools.
		  Return mEnabled
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function AllowedRootsDescription() As String
		  // Human-readable list of the allowed roots, for error messages and logging.
		  Return String.FromArray(mRoots, ", ")
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function NormalizePath(path As String) As String
		  // Lexically canonicalise an absolute POSIX path:
		  //   - requires a leading "/" (returns "" for relative or empty paths)
		  //   - resolves "." and ".." segments (".." above root stays at root)
		  //   - collapses duplicate slashes
		  //   - maps the standard macOS symlinked prefixes /tmp, /var and /etc
		  //     to their /private equivalents so comparisons are consistent
		  //
		  // Lexical only by design -- callers pair this with ResolvedOrLexical,
		  // which resolves symlinks, and re-normalise the result.
		  
		  Var t As String = path.Trim
		  Var firstChar As String = t.Left(1)
		  If firstChar <> "/" Then Return ""
		  
		  Var segs() As String = t.Split("/")
		  Var stack() As String
		  
		  For Each seg As String In segs
		    If seg = "" Or seg = "." Then Continue
		    If seg = ".." Then
		      If stack.Count > 0 Then
		        stack.RemoveAt(stack.LastIndex)
		      End If
		      Continue
		    End If
		    stack.Add(seg)
		  Next seg
		  
		  Var joined As String = String.FromArray(stack, "/")
		  Var result As String = "/" + joined
		  
		  // Map macOS symlinked system prefixes to their real /private locations.
		  Var head5 As String = result.Left(5)
		  If result = "/tmp" Or head5 = "/tmp/" Then
		    result = "/private" + result
		  ElseIf result = "/var" Or head5 = "/var/" Then
		    result = "/private" + result
		  ElseIf result = "/etc" Or head5 = "/etc/" Then
		    result = "/private" + result
		  End If
		  
		  Return result
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Validate(path As String, ByRef reason As String) As Boolean
		  // Returns True when the given path is inside one of the allowed roots.
		  // On failure, reason is set to a message suitable for a ToolResult.
		  
		  If Not mEnabled Then
		    reason = "File tools are disabled. Start XMCP with --enable-file-tools to enable them."
		    Return False
		  End If
		  
		  Var norm As String = NormalizePath(path)
		  If norm = "" Then
		    reason = "Path must be absolute: " + path
		    Return False
		  End If

		  // Resolve symlinks before comparing. Lexical normalisation alone lets a
		  // link inside an allowed root point anywhere on the disk.
		  norm = NormalizePath(ResolvedOrLexical(norm))
		  
		  For Each root As String In mRoots
		    If norm = root Then Return True
		    
		    Var prefix As String = root + "/"
		    If root = "/" Then
		      prefix = "/"
		    End If
		    
		    Var prefixLen As Integer = prefix.Length
		    Var head As String = norm.Left(prefixLen)
		    If head = prefix Then Return True
		  Next root
		  
		  Var rootsList As String = String.FromArray(mRoots, ", ")
		  reason = "Access denied: '" + path + "' is outside the allowed file roots (" + rootsList + "). Adjust with --file-root."
		  Return False
		  
		End Function
	#tag EndMethod


	#tag Method, Flags = &h21
		Private Function RealPath(path As String) As String
		  // Resolves symlinks via realpath(3). Returns "" when the path does not
		  // exist, or on platforms without the call, leaving the caller on the
		  // lexical result.

		  #If TargetMacOS Then
		    Declare Function realpath Lib "/usr/lib/libSystem.dylib" (path As CString, resolved As Ptr) As Ptr

		    Var buffer As New MemoryBlock(4096)
		    Var answer As Ptr = realpath(path, buffer)
		    If answer = Nil Then
		      Return ""
		    End If

		    Return buffer.CString(0)
		  #Else
		    #Pragma Unused path
		    Return ""
		  #EndIf

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ResolvedOrLexical(path As String) As String
		  // Symlink-resolved form of an already lexically normalised path.
		  // A file that does not exist yet cannot be resolved directly, so the
		  // parent is resolved instead and the name reattached -- which is exactly
		  // the case that matters when creating a file. Falls back to the input.

		  Var direct As String = RealPath(path)
		  If direct <> "" Then
		    Return direct
		  End If

		  Var segs() As String = path.Split("/")
		  If segs.Count < 2 Then
		    Return path
		  End If

		  Var baseName As String = segs(segs.LastIndex)
		  segs.RemoveAt(segs.LastIndex)

		  Var parent As String = String.FromArray(segs, "/")
		  If parent = "" Then
		    parent = "/"
		  End If

		  Var realParent As String = RealPath(parent)
		  If realParent = "" Then
		    Return path
		  End If

		  If realParent = "/" Then
		    Return "/" + baseName
		  End If

		  Return realParent + "/" + baseName

		End Function
	#tag EndMethod

	#tag Property, Flags = &h21
		Private mEnabled As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mRoots() As String
	#tag EndProperty

	#tag Note, Name = DesignNotes
		FileGuard is the security policy for the write_file / read_file / hash_file tools.
		
		The file tools are DISABLED by default and only registered when the server is
		started with --enable-file-tools. When enabled, access is restricted to the
		directories listed in --file-root (comma-separated absolute paths, default /tmp).
		
		Rationale: the other XMCP tools all go through the Xojo IDE, which forms a
		natural boundary. Direct filesystem access is a larger attack surface (prompt
		injection, confused deputy), so it is opt-in and sandboxed.
		
		Canonicalisation is lexical (dot-segments, duplicate slashes, macOS /private
		prefix mapping) and is then resolved through realpath(3), so a symlink inside
		an allowed root cannot be used to write outside it. For a path that does not
		exist yet the parent is resolved and the name reattached.

		Residual risk: the check and the subsequent open are separate syscalls, so a
		symlink swapped in between the two would still escape. Xojo exposes no
		openat-style primitive, so this is narrowed rather than eliminated.
	#tag EndNote

	#tag ViewBehavior
		#tag ViewProperty
			Name="Name"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
	#tag EndViewBehavior
End Module
#tag EndModule
