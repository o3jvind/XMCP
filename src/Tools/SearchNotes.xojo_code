#tag Class
Protected Class SearchNotes
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("search_notes", "Searches the user's personal Xojo notes, written and curated in the XDOX app. Notes capture the user's own conventions, hard-won fixes and project-specific knowledge — consult them when the user's own habits or prior decisions matter, as a complement to the official docs from search_docs. Notes flagged [possibly outdated] were written for an older Xojo version.")

		  Parameters.Add(New MCPKit.ToolParameter("query", MCPKit.ToolParameterTypes.String_, _
		  "The search term to look for in note titles and bodies.", _
		  False, "", True))

		  Parameters.Add(New MCPKit.ToolParameter("max_results", MCPKit.ToolParameterTypes.Integer_, _
		  "Maximum number of notes to return. Default is 5.", _
		  True, 5, False))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var query As String = ""
		  Var maxResults As Integer = 5
		  For Each arg As MCPKit.ToolArgument In args
		    If arg.Name = "query" Then
		      query = arg.Value.StringValue
		    ElseIf arg.Name = "max_results" Then
		      maxResults = arg.Value.IntegerValue
		    End If
		  Next arg

		  If query = "" Then
		    Return MCPKit.ToolResult.Failure("The query parameter is required.")
		  End If

		  If App.SemanticSearch = Nil Or Not App.SemanticSearch.HasDatabase Then
		    Return MCPKit.ToolResult.Success("No notes database found. Personal notes require the XDOX app (its database also powers this tool).")
		  End If

		  Var result As String = App.SemanticSearch.SearchNotes(query, maxResults)
		  If result = "" Then
		    Return MCPKit.ToolResult.Success("No notes found for: " + query)
		  End If

		  Return MCPKit.ToolResult.Success(result)

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
	#tag EndViewBehavior
End Class
#tag EndClass
