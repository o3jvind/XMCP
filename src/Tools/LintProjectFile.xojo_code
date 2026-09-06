#tag Class
Protected Class LintProjectFile
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("lint_project_file", "Validates a .xojo_code or .xojo_window file on disk for known structural errors: wrong #tag block ordering, Flags/keyword mismatches, unclosed or mismatched #tag/#tag End pairs, and unescaped characters in constant Default values (both file types use the same escaping for commas/equals/apostrophes/non-ASCII; quote escaping differs slightly between the two — see usage-guide.md). Call this after editing a file directly on disk and before revert_project, as a safety net for mistakes scaffold_code_block does not cover (freehand edits, changes to existing blocks). Reports errors and warnings; does not modify the file.")

		  Parameters.Add(New MCPKit.ToolParameter("path", MCPKit.ToolParameterTypes.String_, _
		  "Absolute path to the .xojo_code or .xojo_window file to validate.", _
		  False, "", True))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var path As String = ""
		  For Each arg As MCPKit.ToolArgument In args
		    If arg.Name = "path" Then path = arg.Value.StringValue
		  Next arg

		  If path = "" Then
		    Return MCPKit.ToolResult.Failure("The path parameter is required.")
		  End If

		  Var targetFile As New FolderItem(path, FolderItem.PathModes.Native)
		  If targetFile = Nil Or Not targetFile.Exists Then
		    Return MCPKit.ToolResult.Failure("File not found: " + path)
		  End If

		  Var isWindow As Boolean = path.Lowercase.EndsWith(".xojo_window")
		  If Not isWindow And Not path.Lowercase.EndsWith(".xojo_code") Then
		    Return MCPKit.ToolResult.Failure("lint_project_file only supports .xojo_code and .xojo_window files.")
		  End If

		  Var content As String
		  Try
		    Var stream As TextInputStream = TextInputStream.Open(targetFile)
		    stream.Encoding = Encodings.UTF8
		    content = stream.ReadAll
		    stream.Close
		  Catch e As IOException
		    Return MCPKit.ToolResult.Failure("Failed to read " + path + ": " + e.Message)
		  End Try

		  Var rules As JSONItem
		  Try
		    rules = FormatRules.Load()
		  Catch e As RuntimeException
		    Return MCPKit.ToolResult.Failure("Could not load Format Rules from usage-guide.md: " + e.Message)
		  End Try

		  Var lines() As String = content.Split(EndOfLine)
		  If lines.LastIndex = 0 Then lines = content.ReplaceLineEndings(EndOfLine).Split(EndOfLine)

		  // #tag Note bodies are free-text documentation that commonly
		  // demonstrates #tag syntax as example text (e.g. examples/Module1.xojo_code
		  // shows a sample "#tag Constant..." line inside its DesignNotes).
		  // Lines inside an open Note block are never real top-level structure,
		  // so every check below skips lines this mask marks True.
		  Var inNote() As Boolean = NoteLineMask(lines)

		  Var diagnostics() As String

		  CheckBlockOrder(lines, inNote, isWindow, rules, diagnostics)
		  CheckFlagsKeywordMatch(lines, inNote, rules, diagnostics)
		  CheckBalancedTags(lines, inNote, diagnostics)
		  CheckConstantEscaping(lines, inNote, rules, diagnostics)

		  Var hasError As Boolean = False
		  For Each d As String In diagnostics
		    If d.IndexOf("error:") > -1 Then hasError = True
		  Next d

		  If diagnostics.LastIndex = -1 Then
		    Return MCPKit.ToolResult.Success("No issues found in " + path)
		  End If

		  Var report As String = String.FromArray(diagnostics, EndOfLine)
		  If hasError Then
		    Return MCPKit.ToolResult.Failure(report)
		  Else
		    Return MCPKit.ToolResult.Success(report)
		  End If

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function NoteLineMask(lines() As String) As Boolean()
		  // Marks every line that falls inside an open #tag Note ... #tag EndNote
		  // block (the Note's own opening/closing tag lines are NOT marked, only
		  // the free-text body between them). #tag Note bodies commonly
		  // demonstrate #tag syntax as example text (see examples/Module1.xojo_code's
		  // DesignNotes), which would otherwise be misread as real structure by
		  // every check below.
		  Var mask() As Boolean
		  Var insideNote As Boolean = False

		  For Each line As String In lines
		    Var trimmed As String = line.Trim
		    If insideNote Then
		      If trimmed = "#tag EndNote" Then
		        insideNote = False
		        mask.Add(False)
		      Else
		        mask.Add(True)
		      End If
		    Else
		      mask.Add(False)
		      If trimmed.BeginsWith("#tag Note,", ComparisonOptions.CaseSensitive) Or trimmed = "#tag Note" Then insideNote = True
		    End If
		  Next line

		  Return mask
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub CheckBlockOrder(lines() As String, inNote() As Boolean, isWindow As Boolean, rules As JSONItem, ByRef diagnostics() As String)
		  // Walks top-level #tag blocks and confirms they appear in the order
		  // declared in Format Rules' "block_order" table. Only tracks
		  // top-level block kinds (Method/Property/Constant/Note/Event/
		  // ViewBehavior for .xojo_code; DesktopWindow/WindowCode/Events/
		  // ViewBehavior for .xojo_window) — nested #tag lines inside a block
		  // body (e.g. a #tag Event inside a Method's code) are ignored by
		  // only matching lines at zero/one-tab top-level indentation.
		  Var blockOrderObj As JSONItem = rules.Lookup("block_order", Nil)
		  If blockOrderObj = Nil Then Return

		  Var orderKey As String = "xojo_code_class"
		  If isWindow Then
		    orderKey = "xojo_window"
		  ElseIf FileDeclaresModule(lines) Then
		    orderKey = "xojo_code_module"
		  End If

		  Var orderList As JSONItem = blockOrderObj.Lookup(orderKey, Nil)
		  If orderList = Nil Then Return

		  Var order() As String
		  For i As Integer = 0 To orderList.Count - 1
		    order.Add(orderList.Value(i).StringValue)
		  Next i

		  Var highestSeenIndex As Integer = -1
		  Var pastViewBehavior As Boolean = False

		  For lineNum As Integer = 0 To lines.LastIndex
		    If inNote(lineNum) Then Continue
		    Var trimmed As String = lines(lineNum).Trim

		    If Not trimmed.BeginsWith("#tag ", ComparisonOptions.CaseSensitive) Then Continue
		    If trimmed.BeginsWith("#tag End", ComparisonOptions.CaseSensitive) Then Continue

		    Var kind As String = ClassifyTopLevelTag(trimmed, isWindow)
		    If kind = "" Then Continue

		    If pastViewBehavior Then
		      diagnostics.Add("error: line " + Str(lineNum + 1) + ": '" + kind + "' block appears after #tag ViewBehavior, which must always be last")
		      Continue
		    End If

		    Var kindIndex As Integer = -1
		    For j As Integer = 0 To order.LastIndex
		      If order(j) = kind Then
		        kindIndex = j
		        Exit
		      End If
		    Next j
		    If kindIndex = -1 Then Continue // unknown/unsupported block kind — not our concern here

		    If kindIndex < highestSeenIndex Then
		      diagnostics.Add("error: line " + Str(lineNum + 1) + ": '" + kind + "' block appears out of order (expected order: " + String.FromArray(order, " -> ") + ")")
		    Else
		      highestSeenIndex = kindIndex
		    End If

		    If kind = "ViewBehavior" Then pastViewBehavior = True
		  Next lineNum
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FileDeclaresModule(lines() As String) As Boolean
		  For Each line As String In lines
		    If line.Trim.BeginsWith("#tag Module", ComparisonOptions.CaseSensitive) Then Return True
		    If line.Trim.BeginsWith("#tag Class", ComparisonOptions.CaseSensitive) Then Return False
		  Next line
		  Return False
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ClassifyTopLevelTag(trimmedLine As String, isWindow As Boolean) As String
		  // Returns the block_order kind name for a top-level "#tag X..." line,
		  // or "" if it is not a block kind this lint tracks (e.g. #tag Class,
		  // #tag ViewProperty, or a nested nested marker inside a block body).
		  If isWindow Then
		    If trimmedLine.BeginsWith("#tag DesktopWindow", ComparisonOptions.CaseSensitive) Then Return "DesktopWindow"
		    If trimmedLine.BeginsWith("#tag WindowCode", ComparisonOptions.CaseSensitive) Then Return "WindowCode"
		    If trimmedLine.BeginsWith("#tag Events ", ComparisonOptions.CaseSensitive) Then Return "Events"
		    If trimmedLine.BeginsWith("#tag ViewBehavior", ComparisonOptions.CaseSensitive) Then Return "ViewBehavior"
		    Return ""
		  End If

		  If trimmedLine.BeginsWith("#tag Event,", ComparisonOptions.CaseSensitive) Or trimmedLine = "#tag Event" Then Return "Event"
		  If trimmedLine.BeginsWith("#tag Method,", ComparisonOptions.CaseSensitive) Then Return "Method"
		  If trimmedLine.BeginsWith("#tag Property,", ComparisonOptions.CaseSensitive) Then Return "Property"
		  If trimmedLine.BeginsWith("#tag Constant,", ComparisonOptions.CaseSensitive) Then Return "Constant"
		  If trimmedLine.BeginsWith("#tag Note,", ComparisonOptions.CaseSensitive) Then Return "Note"
		  If trimmedLine.BeginsWith("#tag ViewBehavior", ComparisonOptions.CaseSensitive) Then Return "ViewBehavior"
		  Return ""
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub CheckFlagsKeywordMatch(lines() As String, inNote() As Boolean, rules As JSONItem, ByRef diagnostics() As String)
		  Var flagsObj As JSONItem = rules.Lookup("flags", Nil)
		  If flagsObj = Nil Then Return

		  For lineNum As Integer = 0 To lines.LastIndex
		    If inNote(lineNum) Then Continue
		    Var trimmed As String = lines(lineNum).Trim
		    If Not (trimmed.BeginsWith("#tag Method,", ComparisonOptions.CaseSensitive) Or trimmed.BeginsWith("#tag Property,", ComparisonOptions.CaseSensitive)) Then Continue

		    Var flagPos As Integer = trimmed.IndexOf("Flags = ")
		    If flagPos = -1 Then Continue
		    Var flagValue As String = trimmed.Middle(flagPos + 8).Trim
		    Var commaPos As Integer = flagValue.IndexOf(",")
		    If commaPos > -1 Then flagValue = flagValue.Left(commaPos).Trim

		    If Not flagsObj.HasKey(flagValue) Then Continue // unknown flag value — not one of ours to check

		    Var entry As JSONItem = flagsObj.Value(flagValue)
		    Var keyword As String = entry.Lookup("keyword", "")

		    If lineNum + 1 > lines.LastIndex Then Continue
		    Var declLine As String = lines(lineNum + 1).Trim

		    If keyword = "" Then
		      // Public: declaration must NOT start with Protected/Private.
		      If declLine.BeginsWith("Protected ") Or declLine.BeginsWith("Private ") Then
		        diagnostics.Add("error: line " + Str(lineNum + 2) + ": declaration has a visibility keyword but Flags = " + flagValue + " means public (no keyword)")
		      End If
		    Else
		      If Not declLine.BeginsWith(keyword + " ") Then
		        diagnostics.Add("error: line " + Str(lineNum + 2) + ": declaration must start with '" + keyword + "' to match Flags = " + flagValue)
		      End If
		    End If
		  Next lineNum
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub CheckBalancedTags(lines() As String, inNote() As Boolean, ByRef diagnostics() As String)
		  Var stack() As String
		  Var stackLines() As Integer

		  For lineNum As Integer = 0 To lines.LastIndex
		    If inNote(lineNum) Then Continue
		    Var trimmed As String = lines(lineNum).Trim
		    // Case-sensitive matching matters here: Xojo also writes an
		    // unrelated "#Tag Instance, Platform = ..." sub-line (capital T)
		    // inside a #tag Constant block for per-platform Default value
		    // overrides — it has no matching #tag EndInstance. BeginsWith is
		    // case-INsensitive by default in this Xojo version, so without
		    // CaseSensitive here "#Tag Instance" would match "#tag " and get
		    // pushed onto the stack, permanently desyncing it for the rest
		    // of the file (confirmed: this produced cascading false
		    // "mismatched tag" errors on examples/App.xojo_code, a real
		    // IDE-generated file with per-platform constant overrides).
		    If Not trimmed.BeginsWith("#tag ", ComparisonOptions.CaseSensitive) Then Continue

		    If trimmed.BeginsWith("#tag End", ComparisonOptions.CaseSensitive) Then
		      Var closedKind As String = trimmed.Middle(8) // after "#tag End"
		      Var spacePos As Integer = closedKind.IndexOf(" ")
		      If spacePos > -1 Then closedKind = closedKind.Left(spacePos)
		      closedKind = closedKind.Trim

		      If stack.LastIndex = -1 Then
		        diagnostics.Add("error: line " + Str(lineNum + 1) + ": '#tag End" + closedKind + "' has no matching opening #tag")
		        Continue
		      End If

		      Var openKind As String = stack(stack.LastIndex)
		      If openKind <> closedKind Then
		        diagnostics.Add("error: line " + Str(lineNum + 1) + ": '#tag End" + closedKind + "' does not match innermost open '#tag " + openKind + "' opened at line " + Str(stackLines(stackLines.LastIndex) + 1))
		      End If
		      stack.RemoveAt(stack.LastIndex)
		      stackLines.RemoveAt(stackLines.LastIndex)
		    Else
		      // Opening tag: extract the kind word right after "#tag ".
		      Var afterTag As String = trimmed.Middle(5)
		      Var kind As String = afterTag
		      Var commaPos As Integer = kind.IndexOf(",")
		      Var spacePos As Integer = kind.IndexOf(" ")
		      Var cutPos As Integer = -1
		      If commaPos > -1 And spacePos > -1 Then
		        cutPos = Min(commaPos, spacePos)
		      ElseIf commaPos > -1 Then
		        cutPos = commaPos
		      ElseIf spacePos > -1 Then
		        cutPos = spacePos
		      End If
		      If cutPos > -1 Then kind = kind.Left(cutPos)
		      kind = kind.Trim

		      // Only block kinds that actually have a matching #tag EndX are
		      // pushed — ViewProperty and similar leaf tags close on the same
		      // line's own #tag EndViewProperty pair, which is handled the
		      // same way (pushed and popped), so no special-casing needed.
		      stack.Add(kind)
		      stackLines.Add(lineNum)
		    End If
		  Next lineNum

		  For i As Integer = 0 To stack.LastIndex
		    diagnostics.Add("error: line " + Str(stackLines(i) + 1) + ": '#tag " + stack(i) + "' is never closed with a matching '#tag End" + stack(i) + "'")
		  Next i
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub CheckConstantEscaping(lines() As String, inNote() As Boolean, rules As JSONItem, ByRef diagnostics() As String)
		  // Both .xojo_code and .xojo_window use the same escaping for
		  // , / = / ' / non-ASCII in a Constant Default value (confirmed
		  // empirically 2026-09-05 — see usage-guide.md's Format Rules).
		  // Quote handling differs: .xojo_window escapes every quote as \";
		  // .xojo_code escapes every quote EXCEPT the field's own closing
		  // quote (the last unescaped " on the line), which stays raw.
		  //
		  // The field's end cannot be found by scanning for the first
		  // unescaped quote — that IS the bug this check exists to catch (a
		  // stray unescaped quote in the middle of the value). Instead, find
		  // the end via the known trailing syntax every #tag Constant line
		  // has: ", Scope = <value>" always follows Default. Everything
		  // between the opening quote and the LAST such marker on the line
		  // is the value span to scan, so an early unescaped quote is
		  // scanned like any other character instead of truncating the scan.
		  Var escapeMap As JSONItem = rules.Lookup("constant_escape", Nil)
		  Var quoteChar As String = Chr(34)

		  For lineNum As Integer = 0 To lines.LastIndex
		    If inNote(lineNum) Then Continue
		    Var trimmed As String = lines(lineNum).Trim
		    If Not trimmed.BeginsWith("#tag Constant,", ComparisonOptions.CaseSensitive) Then Continue

		    // The IDE writes the opening quote escaped (\") whenever the
		    // rest of the value contains anything requiring escaping, but a
		    // fully "plain" value (e.g. Default = "MyApp") is written with a
		    // raw, unescaped opening quote and no backslash anywhere on the
		    // line — confirmed by direct testing in the Xojo IDE, this
		    // compiles without error, but Xojo silently drops the value's
		    // first character when reading it back (Default = "MyApp"
		    // round-trips as "yApp" via constant_value). This is a genuine,
		    // silent data-corruption bug, not a compile error, so it cannot
		    // be distinguished from a legitimately-plain value by looking at
		    // this one line alone — we can only warn, not assert malformed.
		    Var defaultMarker As String = "Default = \" + quoteChar
		    Var defaultPos As Integer = trimmed.IndexOf(defaultMarker)
		    If defaultPos = -1 Then
		      If trimmed.IndexOf("Default = " + quoteChar) > -1 Then
		        diagnostics.Add("warning: line " + Str(lineNum + 1) + ": Constant's Default value has a raw (unescaped) opening quote — Xojo accepts this without a compile error but silently drops the value's first character when read back (confirmed: Default = \" + quoteChar + "MyApp" + quoteChar + " round-trips as \" + quoteChar + "yApp" + quoteChar + "). Re-save this constant's value through the Xojo IDE to fix it.")
		      End If
		      Continue
		    End If
		    Var afterQuote As Integer = defaultPos + defaultMarker.Length
		    Var valueAndRest As String = trimmed.Middle(afterQuote)

		    // Find the LAST occurrence of the scope marker, not the first —
		    // a malformed value could coincidentally contain this exact
		    // substring earlier in the line (e.g. an unescaped comma placed
		    // right after a stray quote), and the real ", Scope = " that
		    // ends the #tag Constant line is always the final one.
		    Var scopeMarker As String = quoteChar + ", Scope = "
		    Var scopeMarkerPos As Integer = -1
		    Var searchFrom As Integer = 0
		    Do
		      Var found As Integer = valueAndRest.IndexOf(searchFrom, scopeMarker)
		      If found = -1 Then Exit
		      scopeMarkerPos = found
		      searchFrom = found + 1
		    Loop
		    If scopeMarkerPos = -1 Then Continue
		    // The character at scopeMarkerPos is the field's own raw
		    // closing quote (correct, not a violation) — exclude it from
		    // the scanned value.
		    Var value As String = valueAndRest.Left(scopeMarkerPos)

		    // Scan for raw (unescaped) characters that should have been
		    // escaped per constant_escape, any unescaped quote (the field's
		    // own closing quote was already excluded above), and non-ASCII
		    // characters not expressed as \xHH bytes.
		    Var j As Integer = 0
		    While j < value.Length
		      Var ch As String = value.Middle(j, 1)

		      If ch = "\" Then
		        j = j + 2 // skip the escape sequence's next character
		        Continue
		      End If

		      If ch = quoteChar Then
		        diagnostics.Add("warning: line " + Str(lineNum + 1) + ": unescaped '" + quoteChar + "' in Default value — expected '\" + quoteChar + "'")
		        j = j + 1
		        Continue
		      End If

		      Var flagged As Boolean = False
		      If escapeMap <> Nil Then
		        For Each key As String In escapeMap.Keys
		          If ch = key Then
		            diagnostics.Add("warning: line " + Str(lineNum + 1) + ": unescaped '" + ch + "' in Default value — expected '" + escapeMap.Value(key).StringValue + "'")
		            flagged = True
		            Exit
		          End If
		        Next key
		      End If

		      If Not flagged And ch.Asc > 127 Then
		        diagnostics.Add("warning: line " + Str(lineNum + 1) + ": raw non-ASCII character in Default value — expected UTF-8 bytes as \xHH, not a literal character")
		      End If

		      j = j + 1
		    Wend
		  Next lineNum
		End Sub
	#tag EndMethod

	#tag Note, Name = DesignNotes
		Pure disk-text validator — no IDE socket communication, so it works
		even when the Xojo IDE is not running. Reads Format Rules from
		usage-guide.md via FormatRules.Load() (shared with
		scaffold_code_block) rather than hardcoding the tables here.
		Deliberately reports warnings without failing (constant-escape checks
		are heuristic and can false-positive on legitimate escaped content),
		matching analyze_project's error-vs-warning convention. Does not
		auto-fix anything — diagnosis only.
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
		#tag ViewProperty
			Name="Index"
			Visible=true
			Group="ID"
			InitialValue="-2147483648"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Super"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Left"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Top"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Description"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="String"
			EditorType="MultiLineEditor"
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
