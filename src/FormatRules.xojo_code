#tag Module
Protected Module FormatRules
	#tag Method, Flags = &h0
		Function Load() As JSONItem
		  // Reads the machine-readable "Format Rules" JSON block embedded in
		  // usage-guide.md and parses it. Both ScaffoldCodeBlock and
		  // LintProjectFile call this instead of hardcoding the block-ordering,
		  // Flags, and escape tables — a rule discovered in the field (e.g. a
		  // new escape edge case) is fixed by editing usage-guide.md, no rebuild.
		  Var guideFile As FolderItem = App.ExecutableFile.Parent.Child("usage-guide.md")
		  If guideFile = Nil Or Not guideFile.Exists Then
		    Raise New RuntimeException("usage-guide.md not found next to the XMCP executable — cannot load Format Rules.")
		  End If

		  Var content As String
		  Var stream As TextInputStream = TextInputStream.Open(guideFile)
		  stream.Encoding = Encodings.UTF8
		  content = stream.ReadAll
		  stream.Close

		  Var backtick As String = Chr(96)
		  Var fenceMarker As String = backtick + backtick + backtick
		  Var jsonFenceMarker As String = fenceMarker + "json"

		  Const kMarker As String = "## Format Rules"
		  Var markerPos As Integer = content.IndexOf(kMarker)
		  If markerPos = -1 Then
		    Raise New RuntimeException("usage-guide.md does not contain a '## Format Rules' section.")
		  End If

		  Var afterMarker As String = content.Middle(markerPos)
		  Var fenceStart As Integer = afterMarker.IndexOf(jsonFenceMarker)
		  If fenceStart = -1 Then
		    Raise New RuntimeException("Format Rules section does not contain a json code block.")
		  End If

		  Var jsonStart As Integer = fenceStart + jsonFenceMarker.Length
		  Var fenceEnd As Integer = afterMarker.IndexOf(jsonStart, fenceMarker)
		  If fenceEnd = -1 Then
		    Raise New RuntimeException("Format Rules JSON code block is not closed.")
		  End If

		  Var jsonText As String = afterMarker.Middle(jsonStart, fenceEnd - jsonStart).Trim

		  Var rules As New JSONItem(jsonText)
		  Return rules
		End Function
	#tag EndMethod

	#tag Note, Name = DesignNotes
		Shared source of truth for Xojo project-file formatting rules
		(block ordering, Flags/keyword mapping, .xojo_window Default-value
		escaping), consumed by ScaffoldCodeBlock (generates correct blocks)
		and LintProjectFile (validates existing blocks). The rules live as a
		JSON code block inside usage-guide.md rather than hardcoded here, so a
		rule can be corrected or extended by editing usage-guide.md alone —
		no rebuild of the XMCP binary required.
	#tag EndNote


	#tag ViewBehavior
	#tag EndViewBehavior
End Module
#tag EndModule
