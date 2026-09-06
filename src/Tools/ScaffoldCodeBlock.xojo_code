#tag Class
Protected Class ScaffoldCodeBlock
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("scaffold_code_block", "Generates a correctly formatted #tag block of Xojo project-file text (Method, Property, Constant, Event definition, Shared method, control event handler, or window event handler) for the caller to insert into a .xojo_code or .xojo_window file on disk. Use this instead of hand-writing #tag syntax from memory - it produces the exact Flags/keyword pairing and .xojo_window escaping documented in usage-guide.md's Format Rules block. This tool only generates text; it does not touch any file or the IDE.")

		  Parameters.Add(New MCPKit.ToolParameter("block_kind", MCPKit.ToolParameterTypes.String_, _
		  "The kind of block to generate. Valid values: method, property, constant, event_definition, shared_method, control_event, window_event.", _
		  False, "", True))

		  Parameters.Add(New MCPKit.ToolParameter("visibility", MCPKit.ToolParameterTypes.String_, _
		  "Visibility for method/property/shared_method: public, protected, or private. Ignored for other block_kind values. Default: public.", _
		  True, "public", False))

		  Parameters.Add(New MCPKit.ToolParameter("name", MCPKit.ToolParameterTypes.String_, _
		  "Method/property/constant/event name, or the control name for control_event.", _
		  False, "", True))

		  Parameters.Add(New MCPKit.ToolParameter("event_or_signature", MCPKit.ToolParameterTypes.String_, _
		  "For control_event/window_event: the event signature, e.g. 'Pressed()' or 'Opening()'. For event_definition: the parameter list, e.g. '(newCount As Integer)'. Ignored otherwise.", _
		  True, "", False))

		  Parameters.Add(New MCPKit.ToolParameter("constant_type", MCPKit.ToolParameterTypes.String_, _
		  "For block_kind = constant only: String, Integer, Double, Boolean, or Color.", _
		  True, "String", False))

		  Parameters.Add(New MCPKit.ToolParameter("default_value", MCPKit.ToolParameterTypes.String_, _
		  "For block_kind = constant only: the raw, unescaped default value. This tool escapes it automatically (quotes, commas, equals signs, apostrophes, non-ASCII bytes) — the same escaping applies whether the block is inserted into a .xojo_code or .xojo_window file.", _
		  True, "", False))

		  Parameters.Add(New MCPKit.ToolParameter("target_file_type", MCPKit.ToolParameterTypes.String_, _
		  "The file this block will be inserted into: xojo_code or xojo_window. Informational only — Constant Default escaping is identical for both file types, confirmed empirically.", _
		  True, "xojo_code", False))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var blockKind As String = ""
		  Var visibility As String = "public"
		  Var itemName As String = ""
		  Var eventOrSignature As String = ""
		  Var constantType As String = "String"
		  Var defaultValue As String = ""
		  Var targetFileType As String = "xojo_code"

		  For Each arg As MCPKit.ToolArgument In args
		    Select Case arg.Name
		    Case "block_kind"
		      blockKind = arg.Value.StringValue
		    Case "visibility"
		      visibility = arg.Value.StringValue
		    Case "name"
		      itemName = arg.Value.StringValue
		    Case "event_or_signature"
		      eventOrSignature = arg.Value.StringValue
		    Case "constant_type"
		      constantType = arg.Value.StringValue
		    Case "default_value"
		      defaultValue = arg.Value.StringValue
		    Case "target_file_type"
		      targetFileType = arg.Value.StringValue
		    End Select
		  Next arg

		  If blockKind = "" Then
		    Return MCPKit.ToolResult.Failure("The block_kind parameter is required.")
		  End If
		  If itemName = "" Then
		    Return MCPKit.ToolResult.Failure("The name parameter is required.")
		  End If

		  Var validKinds() As String = Array("method", "property", "constant", _
		  "event_definition", "shared_method", "control_event", "window_event")
		  Var isValidKind As Boolean = False
		  For Each vk As String In validKinds
		    If vk = blockKind Then
		      isValidKind = True
		      Exit
		    End If
		  Next vk
		  If Not isValidKind Then
		    Return MCPKit.ToolResult.Failure("Invalid block_kind: " + blockKind + ". Valid values: " + String.FromArray(validKinds, ", "))
		  End If

		  Var rules As JSONItem
		  Try
		    rules = FormatRules.Load()
		  Catch e As RuntimeException
		    Return MCPKit.ToolResult.Failure("Could not load Format Rules from usage-guide.md: " + e.Message)
		  End Try

		  Var flagInfo As JSONItem = FlagsFor(rules, visibility)
		  If flagInfo = Nil Then
		    Return MCPKit.ToolResult.Failure("Invalid visibility: " + visibility + ". Valid values: public, protected, private.")
		  End If
		  Var flagValue As String = flagInfo.Lookup("flag", "&h0")
		  Var keyword As String = flagInfo.Lookup("keyword", "")
		  Var keywordPrefix As String = If(keyword <> "", keyword + " ", "")
		  Var q As String = Chr(34)
		  Var t As String = Chr(9)

		  Var blockText As String

		  Select Case blockKind
		  Case "method"
		    blockText = _
		    t + "#tag Method, Flags = " + flagValue + EndOfLine + _
		    t + t + keywordPrefix + "Sub " + itemName + "()" + EndOfLine + _
		    t + t + t + EndOfLine + _
		    t + t + "End Sub" + EndOfLine + _
		    t + "#tag EndMethod"

		  Case "shared_method"
		    blockText = _
		    t + "#tag Method, Flags = " + flagValue + EndOfLine + _
		    t + t + keywordPrefix + "Shared Sub " + itemName + "()" + EndOfLine + _
		    t + t + t + EndOfLine + _
		    t + t + "End Sub" + EndOfLine + _
		    t + "#tag EndMethod"

		  Case "property"
		    blockText = _
		    t + "#tag Property, Flags = " + flagValue + EndOfLine + _
		    t + t + keywordPrefix + itemName + " As String" + EndOfLine + _
		    t + "#tag EndProperty"

		  Case "constant"
		    Var validTypes() As String = Array("String", "Integer", "Double", "Boolean", "Color")
		    Var isValidType As Boolean = False
		    For Each vt As String In validTypes
		      If vt = constantType Then
		        isValidType = True
		        Exit
		      End If
		    Next vt
		    If Not isValidType Then
		      Return MCPKit.ToolResult.Failure("Invalid constant_type: " + constantType + ". Valid values: " + String.FromArray(validTypes, ", "))
		    End If

		    Var escapedDefault As String = EscapeConstantDefault(rules, defaultValue)

		    Var scope As String = flagInfo.Lookup("visibility", "public")
		    scope = scope.Left(1).Uppercase + scope.Right(scope.Length - 1)

		    // The opening quote is always written escaped (\"), even for a
		    // fully "plain" value with nothing else to escape. The IDE
		    // itself omits this escaping for plain values — confirmed
		    // directly in the Xojo IDE that this is a genuine, silent
		    // data-corruption bug: Default = "MyApp" (raw opening quote, no
		    // backslash anywhere) compiles with no error but round-trips as
		    // "yApp" when read back via constant_value, silently dropping
		    // the first character. Always escaping here means this tool's
		    // output can never hit that bug, even though it diverges from
		    // the IDE's own minimal-escaping style for plain values.
		    blockText = _
		    t + "#tag Constant, Name = " + itemName + ", Type = " + constantType + _
		    ", Dynamic = False, Default = \" + q + escapedDefault + q + ", Scope = " + scope + EndOfLine + _
		    t + "#tag EndConstant"

		  Case "event_definition"
		    Var eventSig As String = If(eventOrSignature <> "", eventOrSignature, "()")
		    blockText = _
		    t + "#tag Hook, Flags = " + flagValue + EndOfLine + _
		    t + t + keywordPrefix + "Event " + itemName + eventSig + EndOfLine + _
		    t + "#tag EndHook"

		  Case "control_event"
		    Var sig As String = If(eventOrSignature <> "", eventOrSignature, "EventName()")

		    blockText = _
		    "#tag Events " + itemName + EndOfLine + _
		    t + "#tag Event" + EndOfLine + _
		    t + t + "Sub " + sig + EndOfLine + _
		    t + t + t + EndOfLine + _
		    t + t + "End Sub" + EndOfLine + _
		    t + "#tag EndEvent" + EndOfLine + _
		    "#tag EndEvents"

		  Case "window_event"
		    Var sig As String = If(eventOrSignature <> "", eventOrSignature, "Opening()")

		    blockText = _
		    t + "#tag Event" + EndOfLine + _
		    t + t + "Sub " + sig + EndOfLine + _
		    t + t + t + EndOfLine + _
		    t + t + "End Sub" + EndOfLine + _
		    t + "#tag EndEvent"

		  End Select

		  Return MCPKit.ToolResult.Success(blockText)

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FlagsFor(rules As JSONItem, visibility As String) As JSONItem
		  // Maps a visibility name (public/protected/private) to its
		  // {flag, keyword, visibility} entry in the "flags" object of the
		  // Format Rules JSON - this is a reverse lookup since the JSON is
		  // keyed by flag value (&h0/&h1/&h21), not by visibility name.
		  Var flagsObj As JSONItem = rules.Lookup("flags", Nil)
		  If flagsObj = Nil Then Return Nil

		  Var wanted As String = visibility.Trim.Lowercase
		  For Each key As String In flagsObj.Keys
		    Var entry As JSONItem = flagsObj.Value(key)
		    If entry.Lookup("visibility", "") = wanted Then
		      Var withFlag As New JSONItem
		      withFlag.Value("flag") = key
		      withFlag.Value("keyword") = entry.Lookup("keyword", "")
		      withFlag.Value("visibility") = wanted
		      Return withFlag
		    End If
		  Next key

		  Return Nil
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EscapeConstantDefault(rules As JSONItem, rawValue As String) As String
		  // Escapes a raw constant Default value for embedding between the two
		  // literal quote characters scaffold_code_block itself writes
		  // (Default = " ... "). Confirmed empirically (2026-09-05) by
		  // round-tripping test values through the IDE's constant_value tool
		  // and reading the resulting .xojo_code bytes on disk:
		  //   - , / = / ' / non-ASCII: same \x2C / \x3D / \' / \xHH table in
		  //     BOTH .xojo_code and .xojo_window (not .xojo_window-only, as
		  //     previously assumed).
		  //   - Double quote: .xojo_window escapes every quote as \". In
		  //     .xojo_code every quote in the VALUE escapes as \" too — this
		  //     function only ever sees the value's interior (the caller
		  //     supplies the field's own opening/closing quotes), so escaping
		  //     every quote here is correct for both file types; the "last
		  //     quote on the line stays raw" rule concerns the field's own
		  //     closing quote, which this function does not emit.
		  Var escapeMap As JSONItem = rules.Lookup("constant_escape", Nil)
		  Var quoteChar As String = Chr(34)

		  // Normalize CRLF and lone CR to LF before escaping, so every line
		  // break variant maps to the same \n escape instead of the CR being
		  // silently dropped by the constant_escape table's "\r" -> "" entry
		  // (which exists only to collapse the CR half of a CRLF pair).
		  Var normalized As String = rawValue.ReplaceAll(Chr(13) + Chr(10), Chr(10))
		  normalized = normalized.ReplaceAll(Chr(13), Chr(10))

		  // Backslash-sensitive replacement order matters: escape characters
		  // one at a time over the ORIGINAL string's characters, not the
		  // growing result, to avoid double-escaping already-inserted
		  // backslashes. Build the output character by character instead.
		  Var output As String = ""
		  For i As Integer = 0 To normalized.Length - 1
		    Var ch As String = normalized.Middle(i, 1)
		    Var replaced As Boolean = False

		    If ch = quoteChar Then
		      output = output + "\" + quoteChar
		      replaced = True
		    ElseIf escapeMap <> Nil Then
		      For Each key As String In escapeMap.Keys
		        If ch = key Then
		          output = output + escapeMap.Value(key).StringValue
		          replaced = True
		          Exit
		        End If
		      Next key
		    End If

		    If Not replaced Then
		      If ch.Asc > 127 Then
		        // Non-ASCII: emit raw UTF-8 bytes as \xHH per byte, not \uXXXX.
		        Var data As MemoryBlock = ch.ConvertEncoding(Encodings.UTF8)
		        For b As Integer = 0 To data.Size - 1
		          output = output + "\x" + data.UInt8Value(b).ToHex(2)
		        Next b
		      Else
		        output = output + ch
		      End If
		    End If
		  Next i

		  Return output
		End Function
	#tag EndMethod

	#tag Note, Name = DesignNotes
		Pure text generator - no IDE round-trip, no file I/O beyond reading
		usage-guide.md via FormatRules.Load(). Returns the #tag block text as
		the tool's Success output; the caller inserts it into the target file
		directly (per usage-guide.md's "always edit source files directly on
		disk" doctrine). Pairs with lint_project_file, which validates blocks
		after insertion - scaffold_code_block prevents the four known failure
		modes (block ordering, Flags/keyword mismatch, unclosed tags,
		.xojo_window escape errors) at generation time instead of only
		catching them afterward.

		Note: the Tab global identifier is not usable in this Console app
		target - it produced cascading "item does not exist" compile errors
		affecting the entire method (confirmed via bisection). Use Chr(9)
		(aliased to the local var "t") for indentation instead.
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
