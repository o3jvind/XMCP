#tag Class
Protected Class SearchDocset
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("search_docset", "Searches registered Dash/Zeal .docset bundles by entry name (class, method, function, guide, etc.). Without docset_name, searches all registered docsets and groups results by docset. Use list_docsets to see available docset names.")

		  Parameters.Add(New MCPKit.ToolParameter("query", MCPKit.ToolParameterTypes.String_, _
		  "The search term to look for (e.g. a class, method, or function name).", _
		  False, "", True))

		  Parameters.Add(New MCPKit.ToolParameter("docset_name", MCPKit.ToolParameterTypes.String_, _
		  "Limit the search to a single registered docset by name (as returned by list_docsets). If omitted, all registered docsets are searched.", _
		  True, "", False))

		  Parameters.Add(New MCPKit.ToolParameter("max_results", MCPKit.ToolParameterTypes.Integer_, _
		  "Maximum number of matching entries to return per docset. Default is 10.", _
		  True, 10, False))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var query As String = ""
		  Var docsetName As String = ""
		  Var maxResults As Integer = 10
		  For Each arg As MCPKit.ToolArgument In args
		    If arg.Name = "query" Then
		      query = arg.Value.StringValue
		    ElseIf arg.Name = "docset_name" Then
		      docsetName = arg.Value.StringValue
		    ElseIf arg.Name = "max_results" Then
		      maxResults = arg.Value.IntegerValue
		    End If
		  Next arg

		  If query = "" Then
		    Return MCPKit.ToolResult.Failure("The query parameter is required.")
		  End If

		  If App.Docsets = Nil Or App.Docsets.Count = 0 Then
		    Return MCPKit.ToolResult.Failure("No docsets configured. Use --docset-path to register one or more Dash/Zeal .docset bundles.")
		  End If

		  If docsetName <> "" Then
		    Var target As Docset = FindDocset(docsetName)
		    If target = Nil Then
		      Return MCPKit.ToolResult.Failure("No docset named """ + docsetName + """ is registered. Use list_docsets to see available names.")
		    End If

		    Var result As String = target.Search(query, maxResults)
		    If result = "" Then Return MCPKit.ToolResult.Success("No results found for """ + query + """ in " + target.DocsetName + ".")
		    Return MCPKit.ToolResult.Success("--- " + target.DocsetName + " ---" + EndOfLine + result)
		  End If

		  Var blocks() As String
		  For Each ds As Docset In App.Docsets
		    Var result As String = ds.Search(query, maxResults)
		    If result <> "" Then
		      blocks.Add("--- " + ds.DocsetName + " ---" + EndOfLine + result)
		    End If
		  Next ds

		  If blocks.Count = 0 Then
		    Return MCPKit.ToolResult.Success("No results found for """ + query + """ in any registered docset.")
		  End If

		  Return MCPKit.ToolResult.Success(String.FromArray(blocks, EndOfLine + EndOfLine))

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FindDocset(docsetName As String) As Docset
		  For Each ds As Docset In App.Docsets
		    If ds.DocsetName.Lowercase = docsetName.Lowercase Then Return ds
		  Next ds
		  Return Nil
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
