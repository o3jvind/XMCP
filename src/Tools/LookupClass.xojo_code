#tag Class
Protected Class LookupClass
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("lookup_class", "Looks up documentation for a Xojo class, control, data type or API. By default returns a summary: the page description plus its member tables with signatures. Pass member to get one member's full entry, or full=true for the entire raw reference (large).")

		  Parameters.Add(New MCPKit.ToolParameter("class_name", MCPKit.ToolParameterTypes.String_, _
		  "The name of the class to look up (e.g. 'DesktopButton', 'JSONItem', 'FolderItem', 'String').", _
		  False, "", True))

		  Parameters.Add(New MCPKit.ToolParameter("member", MCPKit.ToolParameterTypes.String_, _
		  "Optional property, method, event or constant name (e.g. 'Middle'). Returns only that member's entry.", _
		  True, "", False))

		  Parameters.Add(New MCPKit.ToolParameter("full", MCPKit.ToolParameterTypes.Boolean_, _
		  "Return the complete unabridged page instead of the summary. Default False.", _
		  True, False, False))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var className As String = ""
		  Var memberName As String = ""
		  Var wantFull As Boolean = False

		  For Each arg As MCPKit.ToolArgument In args
		    Select Case arg.Name.Lowercase
		    Case "class_name"
		      className = arg.Value.StringValue.Trim
		    Case "member"
		      memberName = arg.Value.StringValue.Trim
		    Case "full"
		      wantFull = arg.Value.BooleanValue
		    End Select
		  Next arg

		  If className = "" Then
		    Return MCPKit.ToolResult.Failure("The class_name parameter is required.")
		  End If

		  If App.DocsPath = Nil Then
		    Return MCPKit.ToolResult.Failure("Xojo documentation not found. Use --docs-path to specify the documentation directory, or ensure the Xojo IDE has been run at least once.")
		  End If

		  Var sourcesDir As FolderItem = App.DocsPath.Child("_sources")
		  If sourcesDir = Nil Or Not sourcesDir.Exists Then
		    Return MCPKit.ToolResult.Failure("Documentation _sources directory not found.")
		  End If

		  // Search for the RST file matching the class name.
		  Var targetName As String = className.Lowercase + ".rst.txt"
		  Var foundFile As FolderItem = FindFileRecursive(sourcesDir, targetName)

		  If foundFile = Nil Then
		    // Try without "Desktop" prefix (e.g., "Button" -> "desktopbutton.rst.txt").
		    targetName = "desktop" + className.Lowercase + ".rst.txt"
		    foundFile = FindFileRecursive(sourcesDir, targetName)
		  End If

		  If foundFile = Nil Then
		    // Try without "Web" prefix.
		    targetName = "web" + className.Lowercase + ".rst.txt"
		    foundFile = FindFileRecursive(sourcesDir, targetName)
		  End If

		  If foundFile = Nil Then
		    Return MCPKit.ToolResult.Failure("No documentation found for class: " + className + ". Try using search_docs or list_doc_topics to find the correct name.")
		  End If

		  Const kMaxOutputChars = 102400 // ~100 K characters; counted by character so UTF-8 is never split mid-codepoint

		  // Read the RST file.
		  Try
		    Var tis As TextInputStream = TextInputStream.Open(foundFile)
		    tis.Encoding = Encodings.UTF8
		    Var content As String = tis.ReadAll
		    tis.Close

		    // Anchors are keyed on the page's own file name, so the Desktop/Web
		    // fallbacks above resolve against the page actually opened.
		    Var classKey As String = foundFile.Name.Lowercase
		    If classKey.EndsWith(".rst.txt") Then
		      classKey = classKey.Left(classKey.Length - 8)
		    End If

		    If wantFull Then
		      If content.Length > kMaxOutputChars Then
		        Var footer As String = EndOfLine + "[truncated to first " + kMaxOutputChars.ToString + " of " + content.Length.ToString + " characters - request a single member instead]"
		        Return MCPKit.ToolResult.Success(content.Left(kMaxOutputChars) + footer)
		      End If
		      Return MCPKit.ToolResult.Success(content)
		    End If

		    Var lines() As String = content.ReplaceLineEndings(EndOfLine).Split(EndOfLine)

		    // Each member entry begins with a Sphinx label such as ".. _string.middle:".
		    Var anchorPrefix As String = ".. _" + classKey + "."
		    Var anchorAt() As Integer
		    Var members() As String

		    For i As Integer = 0 To lines.LastIndex
		      Var t As String = lines(i).Trim
		      If t.BeginsWith(anchorPrefix) And t.EndsWith(":") Then
		        anchorAt.Add(i)
		        members.Add(t.Middle(anchorPrefix.Length, t.Length - anchorPrefix.Length - 1))
		      End If
		    Next i

		    If memberName <> "" Then
		      Var wanted As Integer = -1
		      For i As Integer = 0 To members.LastIndex
		        If members(i) = memberName.Lowercase Then
		          wanted = i
		          Exit
		        End If
		      Next i

		      If wanted = -1 Then
		        Return MCPKit.ToolResult.Failure("No member named " + memberName + " on " + className + ". Available members: " + String.FromArray(members, ", "))
		      End If

		      Var lastLine As Integer = lines.LastIndex
		      If wanted < anchorAt.LastIndex Then
		        lastLine = anchorAt(wanted + 1) - 1
		      End If

		      Var section() As String
		      For i As Integer = anchorAt(wanted) To lastLine
		        section.Add(lines(i))
		      Next i

		      Return MCPKit.ToolResult.Success(CleanRST(String.FromArray(section, EndOfLine)))
		    End If

		    // Default: the page overview and its member tables - enough to decide
		    // what to ask for next, without shipping the whole page.
		    Var lastPreambleLine As Integer = lines.LastIndex
		    If anchorAt.Count > 0 Then
		      lastPreambleLine = anchorAt(0) - 1
		    End If

		    Var head() As String
		    For i As Integer = 0 To lastPreambleLine
		      head.Add(lines(i))
		    Next i

		    Var summary As String = CleanRST(String.FromArray(head, EndOfLine))
		    If members.Count > 0 Then
		      summary = summary + EndOfLine + EndOfLine + "--- " + members.Count.ToString + _
		      " documented members on this page. Call lookup_class again with a member name for one member's full entry, or full=true for the whole page. ---"
		    End If

		    Return MCPKit.ToolResult.Success(summary)

		  Catch e As IOException
		    Return MCPKit.ToolResult.Failure("Error reading documentation file: " + e.Message)
		  End Try

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FindFileRecursive(folder As FolderItem, targetName As String) As FolderItem
		  If folder = Nil Or Not folder.Exists Then Return Nil

		  For i As Integer = 0 To folder.Count - 1
		    Var item As FolderItem = folder.ChildAt(i)
		    If item = Nil Then Continue

		    If item.IsFolder Then
		      Var result As FolderItem = FindFileRecursive(item, targetName)
		      If result <> Nil Then Return result
		    Else
		      If item.Name.Lowercase = targetName Then
		        Return item
		      End If
		    End If
		  Next i

		  Return Nil

		End Function
	#tag EndMethod



	#tag Method, Flags = &h21
		Private Function CleanRST(text As String) As String
		  /// Renders a slice of reStructuredText as plain prose: cross-reference
		  /// roles become their display text and table scaffolding is dropped.
		  /// Cosmetic only - no documented content is removed.

		  Return TidyLines(StripRoles(text))

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function StripRoles(text As String) As String
		  /// Rewrites Sphinx roles as their display text, so
		  /// ":ref:`Middle<string.middle>`" and ":doc:`Integer</api/.../integer>`"
		  /// both reduce to the bare name. String indices here are 0-based and
		  /// IndexOf returns -1 when absent (API 2.0).

		  Var out As String
		  Var rest As String = text

		  While True
		    Var refPos As Integer = rest.IndexOf(":ref:`")
		    Var docPos As Integer = rest.IndexOf(":doc:`")

		    If refPos = -1 And docPos = -1 Then
		      Exit
		    End If

		    Var startPos As Integer
		    If refPos = -1 Then
		      startPos = docPos
		    ElseIf docPos = -1 Then
		      startPos = refPos
		    ElseIf refPos < docPos Then
		      startPos = refPos
		    Else
		      startPos = docPos
		    End If

		    // ":ref:" and ":doc:" are both 5 characters; the backtick follows.
		    Var openTick As Integer = startPos + 5
		    Var closeTick As Integer = rest.IndexOf(openTick + 1, "`")
		    If closeTick = -1 Then
		      // Unbalanced markup: leave the remainder exactly as it is.
		      Exit
		    End If

		    Var inner As String = rest.Middle(openTick + 1, closeTick - openTick - 1)
		    Var lt As Integer = inner.IndexOf("<")
		    If lt <> -1 Then
		      inner = inner.Left(lt)
		    End If

		    out = out + rest.Left(startPos) + inner
		    rest = rest.Middle(closeTick + 1)
		  Wend

		  Return out + rest

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function TidyLines(text As String) As String
		  /// Drops directive lines that carry no meaning once the roles are gone,
		  /// then collapses the blank runs their removal leaves behind.

		  Var kept() As String
		  Var blankRun As Integer = 0

		  For Each line As String In text.ReplaceLineEndings(EndOfLine).Split(EndOfLine)
		    Var t As String = line.Trim

		    If t.BeginsWith(".. rst-class::") Or t.BeginsWith(".. csv-table::") _
		      Or t.BeginsWith(":header:") Or t.BeginsWith(":widths:") Then
		      Continue
		    End If

		    If t = "" Then
		      blankRun = blankRun + 1
		      If blankRun > 1 Then
		        Continue
		      End If
		    Else
		      blankRun = 0
		    End If

		    kept.Add(line)
		  Next line

		  Return String.FromArray(kept, EndOfLine).Trim

		End Function
	#tag EndMethod

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
