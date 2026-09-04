#tag Class
Protected Class SearchDocs
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("search_docs", "Searches the local Xojo documentation guides and tutorials by keyword. Returns matching sections with surrounding context. Use this for conceptual questions about language features, patterns, and best practices. To look up a specific class, method, or property by name, use lookup_class instead.")

		  Parameters.Add(New MCPKit.ToolParameter("query", MCPKit.ToolParameterTypes.String_, _
		  "The search term to look for (e.g. 'JSONItem', 'DesktopButton', 'FolderItem', 'database').", _
		  False, "", True))

		  Parameters.Add(New MCPKit.ToolParameter("max_results", MCPKit.ToolParameterTypes.Integer_, _
		  "Maximum number of matching sections to return. Default is 5.", _
		  True, 5, False))

		  Parameters.Add(New MCPKit.ToolParameter("context_lines", MCPKit.ToolParameterTypes.Integer_, _
		  "Number of lines of context to include before and after each match. Default is 10.", _
		  True, 10, False))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var query As String = ""
		  Var maxResults As Integer = 5
		  Var contextLines As Integer = 10
		  For Each arg As MCPKit.ToolArgument In args
		    If arg.Name = "query" Then
		      query = arg.Value.StringValue
		    ElseIf arg.Name = "max_results" Then
		      maxResults = arg.Value.IntegerValue
		    ElseIf arg.Name = "context_lines" Then
		      contextLines = arg.Value.IntegerValue
		    End If
		  Next arg

		  If query = "" Then
		    Return MCPKit.ToolResult.Failure("The query parameter is required.")
		  End If

		  // Tiered search (Task 13):
		  //   1. semantic (hybrid) — needs the RAG DB + the embedding server
		  //   2. keyword (BM25)    — needs only the RAG DB
		  //   3. plain text scan of llms-full.txt — needs neither (last resort)
		  If App.SemanticSearch <> Nil Then
		    If App.SemanticSearch.Available Then
		      Var semanticResult As String = App.SemanticSearch.Search(query, maxResults)
		      If semanticResult <> "" Then
		        Return MCPKit.ToolResult.Success(semanticResult)
		      End If
		    End If
		    Var keywordResult As String = App.SemanticSearch.KeywordSearch(query, maxResults)
		    If keywordResult <> "" Then
		      Return MCPKit.ToolResult.Success(keywordResult)
		    End If
		  End If

		  If App.DocsPath = Nil Then
		    Return MCPKit.ToolResult.Failure("Xojo documentation not found. Use --docs-path to specify the documentation directory, or ensure the Xojo IDE has been run at least once.")
		  End If

		  // Load the full docs text if not cached.
		  If mCachedLines = Nil Or mCachedLines.Count = 0 Then
		    Var llmsFile As FolderItem = App.DocsPath.Child("llms-full.txt")
		    If llmsFile = Nil Or Not llmsFile.Exists Then
		      Return MCPKit.ToolResult.Failure("Could not find llms-full.txt in documentation directory.")
		    End If

		    Try
		      Var tis As TextInputStream = TextInputStream.Open(llmsFile)
		      tis.Encoding = Encodings.UTF8
		      Var allText As String = tis.ReadAll
		      tis.Close
		      mCachedLines = allText.Split(EndOfLine)
		    Catch e As IOException
		      Return MCPKit.ToolResult.Failure("Error reading documentation: " + e.Message)
		    End Try
		  End If

		  // Search for matches.
		  Var lowerQuery As String = query.Lowercase
		  Var results() As String
		  Var lastMatchEnd As Integer = -1
		  Var currentSection As String = ""

		  For i As Integer = 0 To mCachedLines.LastIndex
		    Var line As String = mCachedLines(i)

		    // Track section headers (lines starting with #).
		    If line.BeginsWith("#") Then
		      currentSection = line
		    End If

		    If line.Lowercase.IndexOf(lowerQuery) >= 0 Then
		      // Skip if this match overlaps with a previous context window.
		      If i <= lastMatchEnd Then Continue

		      // Gather context.
		      Var startLine As Integer = Max(0, i - contextLines)
		      Var endLine As Integer = Min(mCachedLines.LastIndex, i + contextLines)
		      lastMatchEnd = endLine

		      Var section() As String
		      If currentSection <> "" Then
		        section.Add("--- Section: " + currentSection + " ---")
		      End If
		      For j As Integer = startLine To endLine
		        If j = i Then
		          section.Add(">>> " + mCachedLines(j))
		        Else
		          section.Add("    " + mCachedLines(j))
		        End If
		      Next j

		      results.Add(String.FromArray(section, EndOfLine))

		      If results.Count >= maxResults Then Exit
		    End If
		  Next i

		  If results.Count = 0 Then
		    Return MCPKit.ToolResult.Success("No results found for: " + query)
		  End If

		  Var output As String = "Found " + results.Count.ToString + " result(s) for """ + query + """:" + EndOfLine + EndOfLine
		  output = output + String.FromArray(results, EndOfLine + EndOfLine)

		  Return MCPKit.ToolResult.Success(output)

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function Max(a As Integer, b As Integer) As Integer
		  If a > b Then Return a
		  Return b

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function Min(a As Integer, b As Integer) As Integer
		  If a < b Then Return a
		  Return b

		End Function
	#tag EndMethod


	#tag Property, Flags = &h21
		Private mCachedLines() As String
	#tag EndProperty


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
