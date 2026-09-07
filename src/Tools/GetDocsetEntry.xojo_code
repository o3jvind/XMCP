#tag Class
Protected Class GetDocsetEntry
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("get_docset_entry", "Reads the full documentation content for a specific entry from a registered Dash/Zeal .docset bundle, as plain text. Use search_docset first to find the exact entry_name.")

		  Parameters.Add(New MCPKit.ToolParameter("docset_name", MCPKit.ToolParameterTypes.String_, _
		  "The registered docset to read from (as returned by list_docsets).", _
		  False, "", True))

		  Parameters.Add(New MCPKit.ToolParameter("entry_name", MCPKit.ToolParameterTypes.String_, _
		  "The exact entry name to read (as returned by search_docset).", _
		  False, "", True))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var docsetName As String = ""
		  Var entryName As String = ""
		  For Each arg As MCPKit.ToolArgument In args
		    If arg.Name = "docset_name" Then
		      docsetName = arg.Value.StringValue
		    ElseIf arg.Name = "entry_name" Then
		      entryName = arg.Value.StringValue
		    End If
		  Next arg

		  If docsetName = "" Then
		    Return MCPKit.ToolResult.Failure("The docset_name parameter is required.")
		  End If
		  If entryName = "" Then
		    Return MCPKit.ToolResult.Failure("The entry_name parameter is required.")
		  End If

		  If App.Docsets = Nil Or App.Docsets.Count = 0 Then
		    Return MCPKit.ToolResult.Failure("No docsets configured. Use --docset-path to register one or more Dash/Zeal .docset bundles.")
		  End If

		  Var target As Docset
		  For Each ds As Docset In App.Docsets
		    If ds.DocsetName.Lowercase = docsetName.Lowercase Then
		      target = ds
		      Exit
		    End If
		  Next ds

		  If target = Nil Then
		    Return MCPKit.ToolResult.Failure("No docset named """ + docsetName + """ is registered. Use list_docsets to see available names.")
		  End If

		  Const kMaxOutputChars = 102400 // ~100 K characters; counted by character so UTF-8 is never split mid-codepoint

		  Var content As String = target.GetEntry(entryName)
		  If content = "" Then
		    Return MCPKit.ToolResult.Failure("No entry named """ + entryName + """ found in " + target.DocsetName + ". Use search_docset to find the correct name.")
		  End If

		  If content.Length > kMaxOutputChars Then
		    Var truncated As String = content.Left(kMaxOutputChars)
		    Var footer As String = EndOfLine + "[truncated to first " + kMaxOutputChars.ToString + " of " + content.Length.ToString + " characters]"
		    Return MCPKit.ToolResult.Success(truncated + footer)
		  End If

		  Return MCPKit.ToolResult.Success(content)

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
